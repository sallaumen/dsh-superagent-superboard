defmodule AgentBoard.Board.PrivateContextTest do
  use ExUnit.Case, async: false

  alias AgentBoard.Board.PrivateContext
  alias AgentBoard.Intake.IssueBody

  @repo %{id: 7, owner: "fixture", name: "private"}

  setup do
    root = Path.join(System.tmp_dir!(), "pc-root-#{System.unique_integer([:positive])}")
    # The source of a folder import must sit under $HOME, outside hidden folders.
    home = Path.expand("~")
    source = Path.join(home, "agent-board-test-#{System.unique_integer([:positive])}")
    previous = Application.get_env(:agent_board, :private_root)
    Application.put_env(:agent_board, :private_root, root)

    on_exit(fn ->
      Application.put_env(:agent_board, :private_root, previous)
      File.rm_rf!(root)
      File.rm_rf!(source)
    end)

    %{root: root, source: source}
  end

  test "each request gets its own folder, and its levels are 0700", %{root: root} do
    dir = PrivateContext.new_request_dir()
    assert dir =~ ~r/\Areq-[0-9a-f]{16}\z/
    assert PrivateContext.valid_dir?(dir)
    # The same words later are another request: never an older one's secrets.
    refute dir == PrivateContext.new_request_dir()

    assert :ok = PrivateContext.write_note(@repo, dir, "senha: hunter2")
    assert PrivateContext.read_note(@repo, dir) == "senha: hunter2"

    path = PrivateContext.path(@repo, dir)
    assert String.starts_with?(path, root)
    assert mode(path) == 0o700
    assert mode(root) == 0o700
    assert mode(Path.join(path, "notes.md")) == 0o600
  end

  test "a file keeps a safe name and its role" do
    dir = PrivateContext.issue_dir(12)

    assert {:ok, "files/before--login_mock.png"} =
             PrivateContext.put_file(@repo, dir, "../login mock.png", "PNG", "before")

    assert {:ok, "files/x.png"} = PrivateContext.put_file(@repo, dir, "x.png", "PNG", "evil")

    assert [%{path: "files/before--login_mock.png", image?: true}, %{path: "files/x.png"}] =
             PrivateContext.list(@repo, dir)
  end

  test "only a raster image at a plain path is served" do
    dir = PrivateContext.issue_dir(3)
    {:ok, _} = PrivateContext.put_file(@repo, dir, "a.png", "PNG")
    {:ok, _} = PrivateContext.put_file(@repo, dir, "page.html", "<script>")

    assert {:ok, "PNG", :png} = PrivateContext.image(@repo, dir, "files/a.png")
    assert :error = PrivateContext.image(@repo, dir, "files/page.html")
    assert :error = PrivateContext.image(@repo, dir, "notes.md")
    assert :error = PrivateContext.image(@repo, dir, "../../other/files/a.png")
    assert :error = PrivateContext.image(@repo, "issue-0", "files/a.png")
    assert :error = PrivateContext.image(@repo, "../etc", "files/a.png")
  end

  test "a link inside the folder is never followed", %{source: source} do
    dir = PrivateContext.issue_dir(4)
    File.mkdir_p!(source)
    File.write!(Path.join(source, "secret.png"), "PNG")
    {:ok, _} = PrivateContext.put_file(@repo, dir, "a.png", "PNG")
    files = Path.join(PrivateContext.path(@repo, dir), "files")
    File.ln_s!(source, Path.join(files, "linked"))

    assert :error = PrivateContext.image(@repo, dir, "files/linked/secret.png")
    assert :error = PrivateContext.remove_file(@repo, dir, "files/linked/secret.png")
    assert File.exists?(Path.join(source, "secret.png"))
    refute Enum.any?(PrivateContext.list(@repo, dir), &String.contains?(&1.path, "linked"))
  end

  test "a folder is copied whole, skipping tool folders and links", %{source: source} do
    File.mkdir_p!(Path.join([source, "screens", "login"]))
    File.mkdir_p!(Path.join(source, "node_modules/x"))
    File.write!(Path.join([source, "screens", "login", "before.png"]), "PNG")
    File.write!(Path.join(source, "index.html"), "<html>")
    File.write!(Path.join(source, "node_modules/x/big.js"), "x")
    File.write!(Path.join(source, ".env"), "SECRET=1")
    File.ln_s!("/etc/hosts", Path.join(source, "hosts"))

    dir = PrivateContext.issue_dir(5)

    assert {:ok, %{files: 2, bytes: 9, name: name}} =
             PrivateContext.import_folder(@repo, dir, source)

    paths = Enum.map(PrivateContext.list(@repo, dir), & &1.path)
    assert "files/#{name}/screens/login/before.png" in paths
    assert "files/#{name}/index.html" in paths
    refute Enum.any?(paths, &(&1 =~ ~r/node_modules|\.env|hosts/))
  end

  test "a folder outside home, hidden, inside the private root or too big is refused",
       %{source: source, root: root} do
    dir = PrivateContext.issue_dir(6)
    assert {:error, :outside_home} = PrivateContext.import_folder(@repo, dir, "/etc")
    assert {:error, :hidden} = PrivateContext.import_folder(@repo, dir, "~/.ssh")
    assert {:error, :not_a_folder} = PrivateContext.import_folder(@repo, dir, source)

    # The private root under home would copy the folder into itself.
    inside = Path.join(Path.expand("~"), "agent-board-root-#{System.unique_integer([:positive])}")
    Application.put_env(:agent_board, :private_root, inside)
    File.mkdir_p!(Path.join(inside, "x"))

    assert {:error, :inside_private} =
             PrivateContext.import_folder(@repo, dir, Path.join(inside, "x"))

    File.rm_rf!(inside)
    Application.put_env(:agent_board, :private_root, root)

    File.mkdir_p!(source)
    for n <- 1..2_001, do: File.write!(Path.join(source, "f#{n}.txt"), "")
    assert {:error, :too_large} = PrivateContext.import_folder(@repo, dir, source)
  end

  test "a task finds its folder through the marker in its body, or the one made for its issue" do
    dir = PrivateContext.new_request_dir()
    body = IssueBody.with_private("Corpo", dir, PrivateContext.shared_path(@repo, dir), "pt")

    assert body =~ "## Contexto privado"
    assert body =~ PrivateContext.shared_path(@repo, dir)
    assert body =~ "Nunca copie esse conteúdo"
    assert PrivateContext.for_task(@repo, %{body: body, number: 9}) == dir
    # The board shows the panel instead of the section.
    assert IssueBody.without_attachments(body) == "Corpo"

    assert PrivateContext.for_task(@repo, %{body: "nada", number: 9}) == nil
    :ok = PrivateContext.write_note(@repo, "issue-9", "x")
    assert PrivateContext.for_task(@repo, %{body: "nada", number: 9}) == "issue-9"
  end

  test "an empty or relative path never means the board's own checkout", %{source: source} do
    dir = PrivateContext.issue_dir(7)
    assert {:error, :not_a_folder} = PrivateContext.check_folder("")
    assert {:error, :not_a_folder} = PrivateContext.check_folder("   ")
    assert {:error, :not_a_folder} = PrivateContext.import_folder(@repo, dir, "lib")
    assert {:error, :not_a_folder} = PrivateContext.check_folder("./")

    # A link under home that leads elsewhere is refused before anything is read.
    File.mkdir_p!(source)
    File.ln_s!("/etc", Path.join(source, "out"))
    assert {:error, :outside_home} = PrivateContext.check_folder(Path.join(source, "out"))
  end

  test "an unreadable file is left out instead of stopping the copy", %{source: source} do
    File.mkdir_p!(source)
    File.write!(Path.join(source, "ok.png"), "PNG")
    locked = Path.join(source, "locked.png")
    File.write!(locked, "PNG")
    File.chmod!(locked, 0o000)
    on_exit(fn -> File.chmod(locked, 0o600) end)

    assert {:ok, %{files: 1}} =
             PrivateContext.import_folder(@repo, PrivateContext.issue_dir(8), source)
  end

  test "the path GitHub sees starts at ~ when the root is under home" do
    home_root = Path.join(Path.expand("~"), ".local/share/agent-board/private")
    Application.put_env(:agent_board, :private_root, home_root)

    assert PrivateContext.shared_path(@repo, "issue-3") ==
             "~/.local/share/agent-board/private/fixture/private/issue-3"

    refute PrivateContext.shared_path(@repo, "issue-3") =~ Path.expand("~")
  end

  test "the note keeps a ceiling" do
    big = String.duplicate("a", 256_001)
    assert {:error, :too_large} = PrivateContext.write_note(@repo, "issue-1", big)
  end

  defp mode(path), do: Bitwise.band(File.stat!(path).mode, 0o777)
end
