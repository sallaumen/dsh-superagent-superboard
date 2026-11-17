defmodule AgentBoard.Intake.ReviewGuides do
  @moduledoc """
  Match the proposal's verification method to known guides. Repository links
  come from the destination tree. Machine-only suggestions disclose a name
  only when selected; neither a model response nor form input supplies a URL.
  """

  @catalog %{
    "motion" => {~w(docs/MOTION_REVIEW.md docs/ui-motion.md), ~w(motion-designer ui-review)},
    "interaction" => {[], ~w(ui-review)},
    "performance" => {[], ~w(ripwire-perf-target)},
    "regression" => {[], ~w(ripwire-write-tests)},
    "inspection" => {[], []}
  }

  @spec methods() :: [String.t()]
  def methods, do: Map.keys(@catalog)

  @doc "Known project guides and bounded, portable skill IDs from GitHub tree entries only."
  @spec from_tree([map()]) :: [String.t()]
  def from_tree(tree) do
    known = @catalog |> Map.values() |> Enum.flat_map(&paths/1)

    files =
      for %{"type" => "blob", "path" => path} = entry <- tree, entry["mode"] != "120000", do: path

    custom =
      files
      |> Enum.filter(&Regex.match?(~r|^\.agents/skills/[a-z][a-z0-9-]{0,63}/SKILL\.md\z|, &1))
      |> Enum.sort()
      |> Enum.take(32)

    Enum.uniq(Enum.filter(known, &(&1 in files)) ++ custom)
  end

  defp paths({guides, skills}) do
    guides ++ for(name <- skills, do: ".agents/skills/#{name}/SKILL.md")
  end

  @doc "One catalog lookup per split, never in a render or on publication."
  @spec available(map() | nil, [String.t()]) :: map()
  def available(repository, roots \\ roots()) do
    project_guides =
      Map.new((repository && repository.paths) || [], fn path ->
        {path, %{id: path, scope: :project, url: "#{repository.url}/blob/HEAD/#{path}"}}
      end)

    methods =
      Map.new(@catalog, fn {method, {_docs, skills} = group} ->
        project =
          for path <- paths(group), guide = project_guides[path], do: guide

        local =
          for name <- skills,
              not Enum.any?(project, &(&1.id == ".agents/skills/#{name}/SKILL.md")),
              Enum.any?(roots, &File.regular?(Path.join([&1, name, "SKILL.md"]))) do
            %{id: name, scope: :local}
          end

        {method, project ++ local}
      end)

    %{methods: methods, project: project_guides}
  end

  defp roots do
    case System.user_home() do
      nil -> []
      home -> Enum.map([".agents/skills", ".codex/skills"], &Path.join(home, &1))
    end
  end

  @spec attach(map(), map()) :: map()
  def attach(task, catalog) do
    {requested, task} = Map.pop(task, :project_guide)

    guides =
      Enum.uniq(
        List.wrap(catalog.project[requested]) ++ Map.fetch!(catalog.methods, task.review_method)
      )

    picked = for %{id: id, scope: :project} <- guides, do: id
    Map.merge(task, %{guides: guides, selected_guides: picked})
  end

  @spec select(map(), [String.t()]) :: map()
  def select(task, ids) when is_list(ids) do
    picked = for %{id: id} <- Map.get(task, :guides, []), id in ids, do: id
    Map.put(task, :selected_guides, picked)
  end
end
