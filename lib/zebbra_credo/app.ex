defmodule ZebbraCredo.App do
  @moduledoc """
  The namespaces and source paths of the app a check runs on, derived from its
  root module.
  """

  @enforce_keys [:module, :web, :lib, :web_lib, :repo]
  defstruct [:module, :web, :lib, :web_lib, :repo]

  @type t :: %__MODULE__{module: module(), web: module(), lib: String.t(), web_lib: String.t(), repo: module()}

  @doc """
  Builds the app for `module`. Options: `:web` (default `<module>Web`) and
  `:repo` (default `<module>.Repo`).
  """
  @spec new(module(), keyword()) :: t()
  def new(module, opts \\ []) do
    web = Keyword.get(opts, :web) || Module.concat([inspect(module) <> "Web"])

    %__MODULE__{
      module: module,
      web: web,
      lib: path(module),
      web_lib: path(web),
      repo: Keyword.get(opts, :repo) || Module.concat(module, Repo)
    }
  end

  defp path(module), do: Path.join("lib", Macro.underscore(inspect(module)))
end
