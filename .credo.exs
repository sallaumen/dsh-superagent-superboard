# Credo strict, with the Phoenix-generated files excluded: they are framework
# code, not ours to restyle.
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          "lib/agent_board_web/components/core_components.ex",
          "lib/agent_board_web.ex",
          "test/support/data_case.ex"
        ]
      },
      strict: true
    }
  ]
}
