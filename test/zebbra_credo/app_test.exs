defmodule ZebbraCredo.AppTest do
  use ExUnit.Case, async: true

  test "new derives web, paths and repo" do
    assert %ZebbraCredo.App{
             module: MyApp,
             web: MyAppWeb,
             lib: "lib/my_app",
             web_lib: "lib/my_app_web",
             repo: MyApp.Repo
           } =
             ZebbraCredo.App.new(MyApp)
  end

  test "new_with_web_override" do
    app = ZebbraCredo.App.new(Acme.Core, web: Acme.Portal)
    assert {app.web, app.lib, app.web_lib} == {Acme.Portal, "lib/acme/core", "lib/acme/portal"}
  end

  test "new_with_repo_override" do
    assert ZebbraCredo.App.new(MyApp, repo: MyApp.Data.Repo).repo == MyApp.Data.Repo
  end
end
