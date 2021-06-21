defmodule MavuSnippets.SnippetGroups do
  @moduledoc """
  The Snippet_Group context.
  """

  alias MavuSnippets.SnippetGroup

  import MavuSnippets, only: [get_conf_val: 2]

  use Memoize
  require Ecto.Query

  def append_content(contents, content) when is_map(content) and is_list(contents) do
    contents ++ [content]
  end

  def get_content_types do
    [
      {:ce_textline_snippet_group, "TextLine-Snippet"},
      {:ce_text_snippet_group, "Text-Snippet"},
      {:ce_html_snippet_group, "Html-Snippet"},
      {:ce_info_snippet_group, "Info-Snippet"}
    ]
  end

  defmemo get_cached_snippet_group(id, conf), expires_in: 300_000 do
    get_snippet_group(id, conf)
  end

  def get_query(_params, _context) do
    SnippetGroup
    |> Ecto.Query.from()
  end

  def get_content_list(id, conf) when is_integer(id),
    do: get_snippet_group(id, conf) |> get_content_list()

  def get_content_list(nil), do: nil

  def get_content_list(%SnippetGroup{} = snippet_group) do
    snippet_group.content
    |> MavuUtils.if_nil([])
  end

  @doc """
  Returns the list of snippet-groups.

  ## Examples

      iex> list_snippet_groups()
      [%SnippetGroup{}, ...]

  """
  def list_snippet_groups(conf) do
    get_conf_val(conf, :repo).all(SnippetGroup)
  end

  @doc """
  Gets a single snippet_group.

  Raises `Ecto.NoResultsError` if the SnippetGroup does not exist.

  ## Examples

      iex> get_snippet_group!(123)
      %SnippetGroup{}

      iex> get_snippet_group!(456)
      ** (Ecto.NoResultsError)

  """
  def get_snippet_group!(id, conf), do: get_conf_val(conf, :repo).get!(SnippetGroup, id)

  def get_snippet_group(id, conf) when is_integer(id),
    do: get_conf_val(conf, :repo).get(SnippetGroup, id)

  def get_snippet_group(path, conf) when is_binary(path),
    do: get_conf_val(conf, :repo).get_by(SnippetGroup, path: SnippetGroup.normalize_path(path))

  @doc """
  Creates a snippet_group.

  ## Examples

      iex> create_snippet_group(%{field: value})
      {:ok, %SnippetGroup{}}

      iex> create_snippet_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_snippet_group(%{} = attrs, conf) do
    res =
      %SnippetGroup{}
      |> SnippetGroup.changeset(attrs)
      |> get_conf_val(conf, :repo).insert()

    invalidate_cache()
    res
  end

  @doc """
  Updates a snippet_group.

  ## Examples

      iex> update_snippet_group(snippet_group, %{field: new_value}, conf)
      {:ok, %SnippetGroup{}}

      iex> update_snippet_group(snippet_group, %{field: bad_value}, conf)
      {:error, %Ecto.Changeset{}}

  """
  def update_snippet_group(%SnippetGroup{} = snippet_group, attrs, conf \\ %{}) do
    res =
      snippet_group
      |> SnippetGroup.changeset(attrs)
      |> get_conf_val(conf, :repo).update()

    # invalidate all cached texts
    invalidate_cache()
    res
  end

  def invalidate_cache() do
    Memoize.invalidate(__MODULE__, :get_cached_snippet_group)
  end

  def duplicate_snippet_group(%SnippetGroup{} = snippet_group, conf) do
    item_data =
      Map.take(snippet_group, SnippetGroup.__schema__(:fields))
      |> Map.delete(:id)

    %SnippetGroup{}
    |> Ecto.Changeset.change(item_data)
    |> get_conf_val(conf, :repo).insert()
  end

  @doc """
  Deletes a snippet_group.

  ## Examples

      iex> delete_snippet_group(snippet_group)
      {:ok, %SnippetGroup{}}

      iex> delete_snippet_group(snippet_group)
      {:error, %Ecto.Changeset{}}

  """
  def delete_snippet_group(%SnippetGroup{} = snippet_group, conf) do
    get_conf_val(conf, :repo).delete(snippet_group)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking snippet-group changes.

  ## Examples

      iex> change_snippet_group(snippet_group)
      %Ecto.Changeset{data: %SnippetGroup{}}

  """
  def change_snippet_group(%SnippetGroup{} = snippet_group, attrs \\ %{}) do
    SnippetGroup.changeset(snippet_group, attrs)
  end
end
