defmodule AgentBoard.AI.Request do
  @moduledoc "What an engine is asked: a model, a system block, a prompt and caps."

  @type t :: %__MODULE__{
          name: atom() | nil,
          model: String.t() | nil,
          system: String.t() | nil,
          prompt: String.t(),
          max_output_tokens: pos_integer(),
          json_schema: map() | nil,
          tier: atom() | nil
        }

  defstruct name: nil,
            model: nil,
            system: nil,
            prompt: "",
            max_output_tokens: 1024,
            json_schema: nil,
            tier: nil

  @doc "A request for a registry spec and the caller's inputs."
  @spec build(map(), map()) :: t()
  def build(spec, inputs) do
    %__MODULE__{
      name: spec.name,
      model: spec.model,
      system: spec.system,
      prompt: prompt(inputs),
      max_output_tokens: spec.output_cap,
      json_schema: spec.json_schema,
      tier: spec.tier
    }
  end

  defp prompt(%{text: text}), do: "Request:\n#{text}"
  defp prompt(%{spec: spec}), do: "Specification:\n#{Jason.encode!(spec, pretty: true)}"
  defp prompt(%{prompt: prompt}), do: prompt
  defp prompt(other), do: "Inputs:\n#{Jason.encode!(other, pretty: true)}"
end
