defmodule MavuSnippets do
  @moduledoc false

  alias MavuSnippets.SnippetGroups

  def default_conf(local_conf \\ %{}) do
    conf_from_env = Application.get_all_env(:mavu_snippets)

    if MavuUtils.present?(conf_from_env) do
      conf_from_env |> Map.new()
    else
      %{
        repo: MyApp.Repo,
        # langs: [l1: "en", l2: "de"]
        langs: [l1: "en"]
      }
    end
    |> Map.merge(local_conf)
  end

  def get_conf_val(conf, key, default \\ nil) when is_atom(key) do
    conf =
      if MavuUtils.empty?(conf) do
        default_conf()
      else
        conf
      end

    Map.get(conf, key, default)
  end

  def get_snippets_in_group!(key, conf \\ %{}) when is_binary(key) or is_integer(key) do
    case SnippetGroups.get_snippet_group(key, conf) do
      snippet_group when is_map(snippet_group) ->
        collect_fields_from_contentlist(snippet_group.content)

      _ ->
        %{}
    end
  end

  def get_or_create_snippet_group(key, conf \\ %{}) when is_binary(key) or is_integer(key) do
    case SnippetGroups.get_cached_snippet_group(key, conf) do
      snippet_group when is_map(snippet_group) ->
        collect_fields_from_contentlist(snippet_group.content)

      _ ->
        create_snippet_group!(key, conf)
    end
  end

  def create_snippet_group!(key, conf \\ %{}) when is_binary(key) do
    {:ok, snippet_group} = SnippetGroups.create_snippet_group(%{path: key, name: key}, conf)
    snippet_group
  end

  def get_snippet_element(snippet_path, opts \\ [])

  def get_snippet_element(snippet_path, opts) when is_binary(snippet_path),
    do: get_snippet_element(parse_snippet_path(snippet_path), opts)

  def get_snippet_element({snippet_group_path, element_name}, opts)
      when is_binary(snippet_group_path) do
    get_snippet_element(
      get_or_create_snippet_group(snippet_group_path, opts[:conf]),
      element_name
    )
    |> case do
      nil ->
        create_snippet_element(snippet_group_path, element_name, opts[:default], nil, opts[:conf])

      val ->
        val
    end
  end

  def get_snippet_element(nil, _), do: nil
  def get_snippet_element(_, nil), do: nil

  def get_snippet_element(snippet_group, element_name)
      when is_map(snippet_group) and is_binary(element_name) do
    snippet_group |> Map.get(element_name)
  end

  @spec create_snippet_element(binary, binary, any, false | nil | binary, map) :: %{
          :path => binary,
          :text_d1 => any,
          :text_l1 => <<_::104>>,
          optional(<<_::24, _::_*16>>) => binary
        }
  def create_snippet_element(
        snippet_group_path,
        element_name,
        default_content,
        ctype \\ nil,
        conf \\ %{}
      )
      when is_binary(snippet_group_path) and is_binary(element_name) and is_map(conf) do
    snippet_group = SnippetGroups.get_snippet_group(snippet_group_path, conf)

    new_element = %{
      path: element_name,
      text_l1: "__use_default",
      text_d1:
        case default_content do
          {:safe, _} -> default_content |> Phoenix.HTML.safe_to_string()
          c -> c
        end
    }

    ctype = ctype || get_ctype_from_element_name(element_name)
    snippet_element = MavuContent.Ce.create(ctype) |> Map.merge(new_element)

    contentlist = MavuContent.Clist.append(snippet_group.content, "root", snippet_element)
    SnippetGroups.update_snippet_group(snippet_group, %{content: contentlist}, conf)

    snippet_element
  end

  def get_ctype_from_element_name(name) when is_binary(name) do
    cond do
      String.ends_with?(name, "_html") -> "ce_html_snippet"
      String.ends_with?(name, "_text") -> "ce_html_snippet"
      String.ends_with?(name, "_plaintext") -> "ce_text_snippet"
      true -> "ce_textline_snippet"
    end
  end

  def parse_snippet_path(snippet_path) when is_binary(snippet_path) do
    [snippet_group_path, fieldname] = String.split(snippet_path, ".")
    {snippet_group_path, fieldname}
  end

  def collect_fields_from_contentlist(contents) when is_list(contents) do
    contents
    |> Enum.filter(fn a -> a["path"] end)
    |> Enum.reduce(%{}, fn el, acc ->
      ce =
        el
        |> AtomicMap.convert(safe: true, ignore: true)
        |> Map.drop(~w(uid path)a)
        |> update_in([:ctype], &clean_ctype/1)

      Map.put(acc, el["path"], ce)
    end)
  end

  def clean_ctype(str) when is_binary(str) do
    str |> String.replace_prefix("ce_", "") |> String.replace_suffix("_snippet", "")
  end

  defdelegate compile(text, values), to: MavuSnippets.SnippetCompiler

  def s(lang_or_params, key, default \\ nil, variables \\ []) do
    {default, variables} =
      cond do
        is_list(default) and default[:do] ->
          {default[:do], default |> Enum.filter(fn {key, _} -> key != :do end)}

        is_list(variables) and variables[:do] ->
          {variables[:do], default}

        true ->
          {default, variables}
      end

    case get_snippet_element(key, default: default, conf: variables[:conf]) do
      el when is_map(el) ->
        get_language_text_from_element(lang_or_params, el, variables[:conf])
        |> MavuSnippets.SnippetCompiler.compile(Keyword.drop(variables, [:do, :conf]))
        |> format_snippet_accordingly(el[:ctype])

      _ ->
        default || "[" <> key <> "]"
    end
  end

  def get_language_text_from_element(lang_or_params, el, conf) when is_map(el) and is_map(conf) do
    case get_text_from_element(lang_from_params(lang_or_params), el) do
      {:ok, text} ->
        text

      _ ->
        get_text_from_element(default_lang(conf), el)
    end
  end

  def get_text_from_element(lang_str, el) when is_binary(lang_str) and is_map(el) do
    langnum = langnum_for_langstr(lang_str)
    text_key = "text_l#{langnum}" |> String.to_existing_atom()
    default_key = "text_d#{langnum}" |> String.to_existing_atom()

    Map.get(el, text_key, "")
    |> case do
      "__use_default" -> Map.get(el, default_key, "")
      text -> text
    end
  end

  def trans(lang_or_params, txt_l1, txt_l2 \\ nil) do
    case lang_from_params(lang_or_params) do
      "en" -> if MavuUtils.present?(txt_l2), do: txt_l2, else: txt_l1
      _ -> txt_l1
    end
  end

  def lang_from_params(lang_or_params, conf \\ %{}) do
    case lang_or_params do
      map when is_map(lang_or_params) -> map["lang"] || map[:lang] || default_lang(conf)
      str when is_binary(str) -> str
      _ -> default_lang(conf)
    end
  end

  def default_lang(conf \\ %{}) do
    get_conf_val(conf, :default_lang, nil)
    |> case do
      lang when is_binary(lang) ->
        if(Enum.member?(available_langs(conf), lang)) do
          lang
        else
          available_langs(conf) |> hd()
        end

      nil ->
        available_langs(conf) |> hd()
    end
  end

  def available_langs(conf) do
    get_conf_val(conf, :langs, []) |> Keyword.values()
  end

  def langnum_for_langstr(lang_or_params, conf \\ %{}) do
    case langnum_map(conf)[lang_from_params(lang_or_params, conf)] do
      num when is_integer(num) -> num
      _ -> 1
    end
  end

  def langnum_map(conf \\ %{}) do
    get_conf_val(conf, :langs, [])
    |> Enum.map(fn {key, langstr} ->
      {langstr, String.trim_leading("#{key}", "l") |> MavuUtils.to_int()}
    end)
    |> Map.new()
  end

  # def get_snippet_text(lang_or_params, key, default \\ nil, variables \\ []) do
  #   case MyApp.Snippets.get_snippet_element(key, default: default) do
  #     el when is_map(el) ->
  #       trans(lang_or_params, el[:text_l1], el[:text_l2])
  #       |> MyApp.Snippets.compile(variables)

  #     _ ->
  #       default || "[" <> key <> "]"
  #   end
  # end

  def format_snippet_accordingly(content, type) do
    case type do
      "textline" -> content
      "text" -> content |> Phoenix.HTML.Format.text_to_html()
      "html" -> content |> Phoenix.HTML.raw()
      _ -> content
    end
  end
end
