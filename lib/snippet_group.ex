defmodule MavuSnippets.SnippetGroup do
  use Ecto.Schema
  import Ecto.Changeset

  schema "snippets" do
    field(:content, {:array, :map})
    field(:path, :string)
    field(:name, :string)
    timestamps()
  end

  use Accessible

  @doc false
  def changeset(snippet, attrs) do
    snippet
    |> cast(attrs, [:name, :path, :content])
    |> update_change(:path, &normalize_path/1)
    |> validate_required([:path])
  end

  def normalize_path(path) do
    Regex.replace(~r([^a-z0-9/-])i, "#{path}", "_")
    |> String.downcase()
    |> String.trim("_")
    |> String.trim("/")
    |> String.trim("_")
  end

  def normalize_slug(path) do
    Regex.replace(~r([^a-z0-9/-])i, "#{path}", "_")
    |> String.downcase()
    |> String.trim("_")
  end
end
