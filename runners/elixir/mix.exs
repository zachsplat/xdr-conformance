defmodule XdrconfElixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :xdrconf_elixir,
      version: "0.1.0",
      elixir: "~> 1.18",
      deps: [{:stellar_base, "== 0.17.0"}, {:jason, "~> 1.4"}]
      
    ]
  end

  def application, do: [extra_applications: [:crypto]]
end
