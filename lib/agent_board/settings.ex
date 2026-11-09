defmodule AgentBoard.Settings do
  @moduledoc """
  Board-wide settings, one row per key.

  The UI writes them (the voice pick, today) and the code reads them; an
  environment variable still wins when it is set. A blank value clears the
  setting, so the code falls back to its default.

  Every change is broadcast on `topic/0` as `{:setting_changed, key}`, so
  every open board follows a change made in another tab, by the API or by a
  spoken command, without a reload.
  """

  import Ecto.Query, warn: false

  alias AgentBoard.Repo
  alias AgentBoard.Settings.Setting

  @topic "settings"

  @doc "The PubSub topic of setting changes."
  def topic, do: @topic

  @doc "Subscribes the caller to `{:setting_changed, key}`."
  def subscribe, do: Phoenix.PubSub.subscribe(AgentBoard.PubSub, @topic)

  @doc "The stored value for a key, or nil."
  @spec get(String.t()) :: String.t() | nil
  def get(key) do
    case Repo.get(Setting, key) do
      nil -> nil
      %Setting{value: value} -> blank_to_nil(value)
    end
  end

  @doc "Stores the value; a blank value removes the key."
  @spec put(String.t(), String.t() | nil) :: :ok | {:error, :invalid}
  def put(key, value) do
    case blank_to_nil(value) do
      nil ->
        Repo.delete_all(from s in Setting, where: s.key == ^key)
        changed(key)

      value ->
        case Repo.insert(
               %Setting{key: key, value: value},
               on_conflict: :replace_all,
               conflict_target: :key
             ) do
          {:ok, _setting} -> changed(key)
          {:error, _changeset} -> {:error, :invalid}
        end
    end
  end

  defp changed(key) do
    Phoenix.PubSub.broadcast(AgentBoard.PubSub, @topic, {:setting_changed, key})
    :ok
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
