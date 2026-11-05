#!/bin/sh
# Runs the five evaluation cases against the live model and prints one line
# per case. This costs real tokens: it is a manual check, never CI.
set -eu
cd "$(dirname "$0")/.."

[ -f .env.local ] || { echo "no .env.local: the model has no key"; exit 1; }

exec mix run -e '
cases = [
  {"lento",  "o board ta lento e as vezes nao carrega"},
  {"voz",    "queria falar com o agente por voz e ele responder"},
  {"bonito", "faz o painel ficar bonito"},
  {"prs",    "cria as tasks do PR 134 e do 135"},
  {"vago",   "não sei, só quero que funcione"}
]

for {label, text} <- cases do
  case AgentBoard.Intake.run(text) do
    {:ok, %{spec: spec, tasks: tasks}} ->
      IO.puts("#{label}\t#{length(tasks)}\t#{spec["goal"]}")
      IO.puts("  questions: #{Enum.join(spec["open_questions"] || [], " | ")}")

    {:error, reason} ->
      IO.puts("#{label}\tERROR\t#{inspect(reason)}")
  end
end
'
