defmodule MavuSnippets.MysqlTypes.JsonArray do
  @behaviour Ecto.Type

  @doc """
  - type should output the name of the DB type
  - cast should receive any type and output your custom Ecto type (=list)
  - load should receive the DB type and output your custom Ecto type
  - dump should receive your custom Ecto type and output the DB type
  """
  def type, do: :string

  def cast(list_data) when is_list(list_data), do: {:ok, list_data}
  def cast(nil), do: {:ok, []}
  def cast(_), do: :error

  def load(value), do: Jason.decode(value)
  def dump(value), do: Jason.encode(value)

  def embed_as(_), do: :self

  def equal?(a, b), do: a == b
end
