defmodule AgentBoard.SecretScanTest do
  @moduledoc """
  No key in the repository: every file git tracks, or would track on the next
  `git add`, is searched for the shapes of the keys this project uses and a
  few common ones. Ignored files (`.env.local`, `deps/`, `_build/`) are left
  alone: that is where secrets belong.

  It is a test so that it runs wherever the suite runs, with no pipeline to
  keep in step: `mix precommit` before a commit, `mix gate` and the CI's
  backend job. To run it alone: `mix test test/secret_scan_test.exs`.

  A finding names the file, the line and the kind of key, never the value. A
  key that reached a commit is compromised even after the line is removed:
  rotate it. A test that needs something shaped like a key builds it at run
  time, as this file does, so no source line holds one.
  """
  use ExUnit.Case, async: true

  @max_bytes 1_000_000

  # A left boundary keeps `voice-ask-shortcut-...` from reading as `sk-...`;
  # the digit keeps out hyphenated words, which real keys never are.
  defp patterns do
    [
      {"OpenAI, DeepSeek or Anthropic key",
       ~r/(?<![A-Za-z0-9])sk-(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{20,}/},
      {"ElevenLabs key", ~r/(?<![A-Za-z0-9])sk_[a-f0-9]{40,}/},
      {"GitHub token",
       ~r/(?<![A-Za-z0-9])(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})/},
      {"Google API key", ~r/(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}/},
      {"AWS access key id", ~r/(?<![A-Za-z0-9])AKIA[0-9A-Z]{16}(?![0-9A-Z])/},
      {"Slack token", ~r/(?<![A-Za-z0-9])xox[baprs]-[A-Za-z0-9-]{10,}/},
      {"private key", ~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/}
    ]
  end

  # [{line number, kind of key}]: where, never what.
  defp find(text) do
    text
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, number} ->
      for {kind, pattern} <- patterns(), Regex.match?(pattern, line), do: {number, kind}
    end)
  end

  defp files do
    {listing, 0} =
      System.cmd("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"])

    String.split(listing, <<0>>, trim: true)
  end

  # Text only: an image or a font has no line to point at.
  defp text(path) do
    with {:ok, %{type: :regular, size: size}} when size <= @max_bytes <- File.stat(path),
         {:ok, content} <- File.read(path),
         true <- String.valid?(content) do
      content
    else
      _ -> ""
    end
  end

  test "no file git tracks or would add holds a key" do
    findings =
      for path <- files(), {line, kind} <- find(text(path)), do: "#{path}:#{line} #{kind}"

    assert findings == [],
           "Something shaped like a key is in the repository:\n  " <>
             Enum.join(findings, "\n  ") <>
             "\nRemove it, keep it in .env.local, and rotate it if it reached a commit."
  end

  test "each kind of key is seen, by line, and the value is never repeated" do
    hex = String.duplicate("0a1b2c3d", 6)

    samples = [
      "OPENAI_API_KEY=sk-proj-" <> hex,
      "key: \"sk-" <> hex <> "\"",
      "ELEVENLABS_API_KEY=sk_" <> hex,
      "token ghp_" <> String.duplicate("A1b2", 9),
      "github_pat_" <> String.duplicate("A1b2_", 13),
      "AIza" <> String.duplicate("a1B2-", 7),
      "aws_access_key_id = AKIA" <> String.duplicate("A1B2", 4),
      "xoxb-" <> "1234567890-abcdef",
      "-----BEGIN " <> "RSA PRIVATE KEY-----"
    ]

    text = Enum.join(["a plain line" | samples], "\n")
    findings = find(text)

    assert Enum.map(findings, &elem(&1, 0)) == Enum.to_list(2..(length(samples) + 1))
    refute inspect(findings) =~ hex
  end

  test "words that only look like a key are not one" do
    assert find("docs/ui-audit/2026-11-05/voice-ask-shortcut/after-1440-light.png") == []
    assert find("the task-list-of-the-day-and-its-sections") == []
    assert find("sk-this-is-a-hyphenated-phrase-without-any-number") == []
    assert find("config :agent_board, openai_api_key: System.get_env(\"OPENAI_API_KEY\")") == []
  end
end
