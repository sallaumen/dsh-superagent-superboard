defmodule AgentBoard.AI.Schema do
  @moduledoc "Validates the JSON Schema subset used by registered AI calls."

  @spec valid?(map() | nil, term()) :: boolean()
  def valid?(nil, value), do: is_map(value)

  def valid?(%{"type" => type} = schema, value) do
    type_valid?(type, value) and enum_valid?(schema, value) and
      children_valid?(type, schema, value)
  end

  def valid?(_schema, _value), do: false

  defp type_valid?("object", value), do: is_map(value)
  defp type_valid?("array", value), do: is_list(value)
  defp type_valid?("string", value), do: is_binary(value)
  defp type_valid?("boolean", value), do: is_boolean(value)
  defp type_valid?("integer", value), do: is_integer(value)
  defp type_valid?(_type, _value), do: false

  defp enum_valid?(%{"enum" => allowed}, value), do: value in allowed
  defp enum_valid?(_schema, _value), do: true

  defp children_valid?("object", schema, value) do
    properties = Map.get(schema, "properties", %{})
    required = Map.get(schema, "required", [])

    # Providers may add fields; only declared fields can affect the consumer.
    Enum.all?(required, &Map.has_key?(value, &1)) and
      Enum.all?(properties, fn {key, child_schema} ->
        not Map.has_key?(value, key) or valid?(child_schema, Map.fetch!(value, key))
      end)
  end

  defp children_valid?("array", schema, value) do
    case Map.get(schema, "items") do
      nil -> true
      item_schema -> Enum.all?(value, &valid?(item_schema, &1))
    end
  end

  defp children_valid?(_type, _schema, _value), do: true
end
