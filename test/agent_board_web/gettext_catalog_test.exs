defmodule AgentBoardWeb.GettextCatalogTest do
  use ExUnit.Case, async: true

  test "every extracted interface message has a Brazilian Portuguese translation" do
    template = Expo.PO.parse_file!("priv/gettext/default.pot")
    portuguese = Expo.PO.parse_file!("priv/gettext/pt_BR/LC_MESSAGES/default.po")

    ids = MapSet.new(template.messages, &message_id/1)
    translations = Map.new(portuguese.messages, &{message_id(&1), &1})

    assert MapSet.new(Map.keys(translations)) == ids

    for {id, message} <- translations do
      assert translated?(message), "Missing Portuguese translation for #{inspect(id)}"

      refute Expo.Message.has_flag?(message, "fuzzy"),
             "Fuzzy Portuguese translation for #{inspect(id)}"
    end
  end

  defp message_id(message), do: IO.iodata_to_binary(message.msgid)

  defp translated?(%Expo.Message.Singular{msgstr: msgstr}),
    do: IO.iodata_to_binary(msgstr) != ""

  defp translated?(%Expo.Message.Plural{msgstr: msgstr}),
    do: Enum.all?(Map.values(msgstr), &(IO.iodata_to_binary(&1) != ""))
end
