defmodule MavuSnippets do
  @moduledoc false

  alias MavuSnippets.SnippetGroups
  alias MavuSnippets.SnippetGroup
  alias MavuContent.Clist

  def default_conf(local_conf \\ %{}) do
    %{
      repo: MyApp.Repo,
      # langs: [l1: "en", l2: "de"]
      langs: [l1: "en"]
    }
    |> Map.merge(Application.get_all_env(:mavu_snippets) |> Map.new())
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

  def get_snippet_element({snippet_group_path, element_slug}, opts)
      when is_binary(snippet_group_path) do
    get_snippet_element(
      get_or_create_snippet_group(snippet_group_path, opts[:conf]),
      element_slug
    )
    |> case do
      nil ->
        create_snippet_element(snippet_group_path, element_slug, opts[:default], nil, opts[:conf])

      val ->
        val
    end
  end

  def get_snippet_element(nil, _), do: nil
  def get_snippet_element(_, nil), do: nil

  def get_snippet_element(snippet_group, element_slug)
      when is_map(snippet_group) and is_binary(element_slug) do
    snippet_group |> Map.get(element_slug)
  end

  def create_snippet_element(
        snippet_group_path,
        element_slug,
        default_content,
        ctype \\ nil,
        conf \\ %{}
      )
      when is_binary(snippet_group_path) and is_binary(element_slug) do
    snippet_group = SnippetGroups.get_snippet_group(snippet_group_path, conf)

    new_element = %{
      "slug" => element_slug,
      "text_l1" => "",
      "text_d1" => default_content |> prepare_default_content()
    }

    ctype = ctype || get_ctype_from_element_slug(element_slug)
    snippet_element = MavuContent.Ce.create(ctype) |> Map.merge(new_element)

    contentlist = Clist.append(snippet_group.content, "root", snippet_element)
    SnippetGroups.update_snippet_group(snippet_group, %{content: contentlist}, conf)

    snippet_element
  end

  def prepare_default_content(default_content) do
    case default_content do
      {:safe, _} -> default_content |> Phoenix.HTML.safe_to_string()
      c -> c
    end
  end

  def get_ctype_from_element_slug(name) when is_binary(name) do
    cond do
      String.ends_with?(name, "_html") -> "ce_html_snippet"
      String.ends_with?(name, "_text") -> "ce_html_snippet"
      String.ends_with?(name, "_plaintext") -> "ce_text_snippet"
      String.ends_with?(name, "_json") -> "ce_text_snippet"
      true -> "ce_textline_snippet"
    end
  end

  def parse_snippet_path(snippet_path) when is_binary(snippet_path) do
    [snippet_group_path, slug] = String.split(snippet_path, ".")
    {snippet_group_path |> SnippetGroup.normalize_path(), slug |> SnippetGroup.normalize_slug()}
  end

  def collect_fields_from_contentlist(contents) when is_list(contents) do
    contents
    |> Enum.filter(fn a -> a["slug"] end)
    |> Enum.reduce(%{}, fn el, acc ->
      ce =
        el
        # |> AtomicMap.convert(safe: true, ignore: true)
        |> Map.drop(~w(uid slug))
        |> update_in(["ctype"], &clean_ctype/1)

      Map.put(acc, el["slug"], ce)
    end)
  end

  def clean_ctype(str) when is_binary(str) do
    str |> String.replace_prefix("ce_", "") |> String.replace_suffix("_snippet", "")
  end

  defdelegate compile(text, values), to: MavuSnippets.SnippetCompiler

  def snip(lang_or_params, path, default \\ nil, variables \\ []) do
    {default, variables} =
      cond do
        is_list(default) and default[:do] ->
          {default[:do], default |> Enum.filter(fn {path, _} -> path != :do end)}

        is_list(variables) and variables[:do] ->
          {variables[:do], default}

        true ->
          {default, variables}
      end

    case get_snippet_element(path, default: default, conf: variables[:conf]) do
      el when is_map(el) ->
        el = update_default_content_in_element_if_needed(el, default, path, variables[:conf])

        {_mode, text} = get_effective_text_from_element(el, lang_or_params, variables[:conf])

        text
        |> MavuSnippets.SnippetCompiler.compile(Keyword.drop(variables, [:do, :conf]))
        |> format_snippet_accordingly(variables[:format_as] || el["ctype"])

      _ ->
        default || "[" <> path <> "]"
    end
  end

  def update_default_content_in_element_if_needed(el, default_content, path, conf \\ %{})

  def update_default_content_in_element_if_needed(el, _default_content = nil, _, _),
    do: el

  def update_default_content_in_element_if_needed(el, default_content, path, conf)
      when is_binary(path) and is_map(el) do
    content2compare = default_content |> prepare_default_content()

    if content2compare != el["text_d1"] do
      update_snippet_element(el, path, %{"text_d1" => content2compare}, conf)
    else
      el
    end
  end

  def update_snippet_element(el, snippet_path, values, conf \\ %{})
      when is_map(el) and is_binary(snippet_path) and is_map(values) do
    {snippet_group_path, element_slug} = parse_snippet_path(snippet_path)

    snippet_group = SnippetGroups.get_snippet_group(snippet_group_path, conf)

    el =
      Clist.get_clist(snippet_group.content, "root")
      |> Enum.find(&(&1["slug"] == element_slug))

    contentlist = Clist.update(snippet_group.content, "root", el["uid"], values)
    {:ok, el} = SnippetGroups.update_snippet_group(snippet_group, %{content: contentlist}, conf)
    el
  end

  def get_default_text_from_element(el, lang_or_params, _conf \\ %{})
      when is_map(el) do
    lang = lang_from_params(lang_or_params)

    langnum = langnum_for_langstr(lang)

    Map.get(el, "text_d#{langnum}", :no_default_text_found)
    |> case do
      :no_default_text_found -> ""
      text -> text
    end
  end

  def get_effective_text_from_element(el, lang_or_params, conf \\ %{})
      when is_map(el) do
    lang = lang_from_params(lang_or_params)
    default_lang = default_lang(conf)

    # {lang, default_lang} |> IO.inspect(label: "mwuits-debug 2021-06-20_18:48 ")

    case get_text_from_element(el, lang) do
      {:custom, text} ->
        {:custom, text}

      {:default, default_text} ->
        if lang == default_lang do
          {:default, default_text}
        else
          case get_text_from_element(el, default_lang) do
            {:custom, text} -> {:fallback, text}
            {:default, _text} -> {:fallback, default_text}
            {:unset, _text} -> {:fallback, default_text}
          end
        end

      {:unset, text} ->
        if lang == default_lang do
          {:unset, text}
        else
          {_mode, text} = get_text_from_element(el, default_lang)
          {:fallback, text}
        end
    end
    |> case do
      {type, nil} -> {type, ""}
      other -> other
    end
  end

  def get_text_from_element(el, lang_str, conf \\ %{})
      when is_binary(lang_str) and is_map(el) do
    langnum = langnum_for_langstr(lang_str, conf)

    Map.get(el, "text_l#{langnum}", :no_text_found)
    |> case do
      empty_text when empty_text in [nil, ""] ->
        case Map.get(el, "text_d#{langnum}", :no_default_text_found) do
          :no_default_text_found -> {:unset, ""}
          text -> {:default, text}
        end

      :no_text_found ->
        {:unset, ""}

      text ->
        {:custom, text}
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

  def format_snippet_accordingly(content, type) do
    case type do
      "textline" -> content
      "text" -> content |> Phoenix.HTML.Format.text_to_html()
      "html" -> content |> Phoenix.HTML.raw()
      _ -> content
    end
  end
end
