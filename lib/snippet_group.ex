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
    |> validate_required([:path])
  end
end
