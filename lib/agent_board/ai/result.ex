defmodule AgentBoard.AI.Result do
  @moduledoc "An engine answer with measured usage. `parse_state` says how much of the schema came back."

  @type t :: %__MODULE__{
          text: String.t(),
          json: map() | nil,
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          duration_ms: non_neg_integer(),
          cost_micros: non_neg_integer(),
          model: String.t() | nil,
          engine: atom() | nil,
          parse_state: :complete | :partial | nil
        }

  defstruct text: "",
            json: nil,
            input_tokens: 0,
            output_tokens: 0,
            duration_ms: 0,
            cost_micros: 0,
            model: nil,
            engine: nil,
            parse_state: nil
end
