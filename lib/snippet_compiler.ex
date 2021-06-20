defmodule MavuSnippets.SnippetCompiler do
  @moduledoc """
  Compile text with provided values.
  """

  @prefix Application.get_env(:mavu_snippets, :var_prefix) || "%{"
  @suffix Application.get_env(:mavu_snippets, :var_suffix) || "}"

  @doc """
  Compile text with provided values.

  ## Parameters

    - `text`: `String` or `List` of strings to compile.
    - `values`: `Map` of values.

  ## Examples

      iex> MavuSnippets.SnippetCompiler.compile("hello %{test}", %{"test" => "world"})
      "hello world"

      iex> MavuSnippets.SnippetCompiler.compile("hello %{test}", %{})
      "hello %{test}"

      iex> MavuSnippets.SnippetCompiler.compile(["hello %{test}", "No.%{nr}"], %{"test" => "world", "nr" => 1})
      ["hello world", "No.1"]
  """
  def compile(texts, values) when is_map(values), do: compile(texts, Map.to_list(values))

  def compile(text, values) when is_bitstring(text) do
    Enum.reduce(values, text, fn {key, value}, result ->
      String.replace(result, variable(key), to_string(value))
    end)
  end

  def compile(texts, values) when is_list(texts) do
    Enum.map(texts, fn text -> compile(text, values) end)
  end

  def compile(nil, _), do: ""

  defp variable(key) do
    "#{@prefix}#{key}#{@suffix}"
  end
end
