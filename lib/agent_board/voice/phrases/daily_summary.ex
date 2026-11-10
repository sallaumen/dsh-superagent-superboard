defmodule AgentBoard.Voice.Phrases.DailySummary do
  @moduledoc """
  The summary of the day as spoken words, per language, built from the facts
  stored in its row (`AgentBoard.DailySummary.Facts`) by template: no model,
  no cost. Reached through `AgentBoard.Voice.Phrases.daily_summary/2`.

  Each executor is said apart, in its own terms; amounts are never added
  across executors. An executor without a source is "not measured", never a
  zero.
  """

  @names %{"deepseek" => "DeepSeek", "claude" => "Claude", "codex" => "Codex"}

  @doc "The whole utterance for one summary."
  @spec say(String.t(), map()) :: String.t()
  def say(lang, content) do
    [
      merged(
        lang,
        get_in(content, ["merged", "count"]) || 0,
        get_in(content, ["merged", "issues"])
      ),
      needs(lang, content["needs"] || %{}),
      sync(lang, content["sync_errors"] || 0),
      retries(lang, content["retries"] || %{}),
      spend(lang, content["spend"] || [])
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # ---- what was done --------------------------------------------------------

  # A row stored before the issues were counted says the PRs alone.
  defp merged(lang, count, nil), do: merged(lang, count)

  defp merged("en-US", count, issues),
    do: "Daily summary: #{issues("en-US", issues)}, #{prs("en-US", count)}."

  defp merged(lang, count, issues),
    do: "Resumo do dia: #{issues(lang, issues)}, #{prs(lang, count)}."

  defp issues("en-US", 0), do: "no issues delivered"
  defp issues("en-US", 1), do: "1 issue delivered"
  defp issues("en-US", n), do: "#{n} issues delivered"
  defp issues(_lang, 0), do: "nenhuma issue entregue"
  defp issues(_lang, 1), do: "1 issue entregue"
  defp issues(_lang, n), do: "#{n} issues entregues"

  defp prs("en-US", 1), do: "1 PR merged"
  defp prs("en-US", n), do: "#{n} PRs merged"
  defp prs(_lang, 1), do: "1 PR mesclado"
  defp prs(_lang, n), do: "#{n} PRs mesclados"

  defp merged("en-US", 0), do: "Daily summary: no PRs merged."
  defp merged("en-US", 1), do: "Daily summary: 1 PR merged."
  defp merged("en-US", n), do: "Daily summary: #{n} PRs merged."
  defp merged(_lang, 0), do: "Resumo do dia: nenhum PR mesclado."
  defp merged(_lang, 1), do: "Resumo do dia: 1 PR mesclado."
  defp merged(_lang, n), do: "Resumo do dia: #{n} PRs mesclados."

  # ---- what still needs the owner ------------------------------------------

  defp needs(lang, needs), do: needs(lang, needs["blocked"] || 0, needs["waiting"] || 0)

  defp needs("en-US", 0, 0), do: "Nothing is waiting for you."
  defp needs("en-US", 1, 0), do: "1 blocked task is waiting for you."
  defp needs("en-US", b, 0), do: "#{b} blocked tasks are waiting for you."
  defp needs("en-US", 0, 1), do: "1 task is waiting for you."
  defp needs("en-US", 0, w), do: "#{w} tasks are waiting for you."

  defp needs("en-US", b, w),
    do:
      "#{b} blocked #{plural(b, "task", "tasks")} and #{w} #{plural(w, "other", "others")} " <>
        "are waiting for you."

  defp needs(_lang, 0, 0), do: "Nada espera você."
  defp needs(_lang, 1, 0), do: "1 tarefa bloqueada espera você."
  defp needs(_lang, b, 0), do: "#{b} tarefas bloqueadas esperam você."
  defp needs(_lang, 0, 1), do: "1 tarefa espera você."
  defp needs(_lang, 0, w), do: "#{w} tarefas esperam você."

  defp needs(_lang, b, w),
    do:
      "#{b} #{plural(b, "tarefa bloqueada", "tarefas bloqueadas")} e " <>
        "#{w} #{plural(w, "outra", "outras")} esperam você."

  defp sync(_lang, 0), do: nil
  defp sync("en-US", 1), do: "The sync failed once."
  defp sync("en-US", n), do: "The sync failed #{n} times."
  defp sync(_lang, 1), do: "A sincronização falhou 1 vez."
  defp sync(_lang, n), do: "A sincronização falhou #{n} vezes."

  # ---- what the board did on its own ----------------------------------------

  defp retries(lang, retries), do: retries(lang, retries["sent"] || 0, retries["tasks"] || 0)

  defp retries(_lang, 0, _tasks), do: nil
  defp retries("en-US", 1, _tasks), do: "I retried once on my own."
  defp retries("en-US", n, tasks) when tasks <= 1, do: "I retried #{n} times on my own."
  defp retries("en-US", n, tasks), do: "I retried #{n} times on my own, on #{tasks} tasks."
  defp retries(_lang, 1, _tasks), do: "Tentei de novo sozinho 1 vez."
  defp retries(_lang, n, tasks) when tasks <= 1, do: "Tentei de novo sozinho #{n} vezes."
  defp retries(_lang, n, tasks), do: "Tentei de novo sozinho #{n} vezes, em #{tasks} tarefas."

  # ---- what each executor spent ---------------------------------------------

  # DeepSeek is always said (it is the executor the board reads); the others
  # are said when measured and grouped as "not measured" otherwise.
  defp spend(lang, lines) do
    {said, unmeasured} =
      Enum.split_with(lines, &(&1["executor"] == "deepseek" or &1["status"] != "unknown"))

    Enum.map(said, &executor(lang, &1)) ++ [unmeasured(lang, unmeasured)]
  end

  defp executor(lang, %{"status" => "measured", "micros" => micros} = line)
       when is_integer(micros) do
    spent(lang, name(line), cents(micros), line["complete"] != false, line["reference"])
  end

  defp executor(lang, %{"status" => "measured", "currency" => "quota"} = line),
    do: quota(lang, name(line), line["percent"])

  defp executor("en-US", %{"status" => "none"} = line), do: "#{name(line)} did not run."
  defp executor(_lang, %{"status" => "none"} = line), do: "O #{name(line)} não rodou."
  defp executor("en-US", line), do: "#{name(line)}'s spending is unknown."
  defp executor(_lang, line), do: "O gasto do #{name(line)} é desconhecido."

  defp spent("en-US", name, 0, _complete, _reference), do: "#{name} spent less than a cent."

  defp spent("en-US", name, cents, complete, "list"),
    do:
      "#{name} spent #{if complete, do: "about", else: "at least"} #{dollars("en-US", cents)} " <>
        "at list price, which is not the bill."

  defp spent("en-US", name, cents, complete, _reference),
    do: "#{name} spent #{if complete, do: "about", else: "at least"} #{dollars("en-US", cents)}."

  defp spent(_lang, name, 0, _complete, _reference),
    do: "O #{name} gastou menos de um centavo de dólar."

  defp spent(_lang, name, cents, complete, "list"),
    do:
      "O #{name} gastou #{if complete, do: "cerca de", else: "pelo menos"} " <>
        "#{dollars("pt-BR", cents)} a preço de lista, que não é a fatura."

  defp spent(lang, name, cents, complete, _reference),
    do:
      "O #{name} gastou #{if complete, do: "cerca de", else: "pelo menos"} #{dollars(lang, cents)}."

  defp quota("en-US", name, percent) when is_number(percent),
    do: "#{name} is at #{round(percent)}% of the weekly quota."

  defp quota(_lang, name, percent) when is_number(percent),
    do: "O #{name} está em #{round(percent)}% da cota semanal."

  defp quota("en-US", name, _percent), do: "#{name}'s weekly quota is unknown."
  defp quota(_lang, name, _percent), do: "A cota semanal do #{name} é desconhecida."

  defp unmeasured(_lang, []), do: nil

  defp unmeasured("en-US", [one]), do: "#{name(one)} is not measured yet."

  defp unmeasured("en-US", many),
    do: "#{many |> Enum.map(&name/1) |> join("and")} are not measured yet."

  defp unmeasured(_lang, lines),
    do: "#{lines |> Enum.map(&name/1) |> join("e")} ainda sem medição."

  defp name(line), do: Map.get(@names, line["executor"], line["executor"])

  defp cents(micros), do: div(micros + 5_000, 10_000)

  defp dollars("en-US", cents) do
    amount = "#{div(cents, 100)}.#{pad(rem(cents, 100))}"
    if cents == 100, do: "#{amount} dollar", else: "#{amount} dollars"
  end

  defp dollars(_lang, cents) do
    amount = "#{div(cents, 100)},#{pad(rem(cents, 100))}"
    if cents < 200, do: "#{amount} dólar", else: "#{amount} dólares"
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp join([one], _conjunction), do: one

  defp join(many, conjunction),
    do: Enum.join(Enum.drop(many, -1), ", ") <> " #{conjunction} " <> List.last(many)

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many
end
