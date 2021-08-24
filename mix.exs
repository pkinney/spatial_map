defmodule SpatialMap.MixProject do
  use Mix.Project

  def project() do
    [
      app: :spatial_map,
      version: "0.1.0",
      description: description(),
      package: package(),
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application() do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps() do
    [
      {:envelope, "~> 1.2.1"},
      {:geo, "~> 3.4"},
      {:topo, "~> 0.4.0"},
      {:jason, "~> 1.2"},
      {:poolboy, "~> 1.5"},
      {:spatial_hash, "~> 0.1.0"},
      {:telemetry, "~> 0.4"},
      {:ex_doc, "~> 0.18", only: :dev},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:benchee, "~> 1.0", only: :dev},
      {:excoveralls, "~> 0.10", only: :test},
      {:geo_stream_data, "~> 0.1", only: :test},
      {:stream_data, "~> 0.5", only: [:dev, :test]}
    ]
  end

  defp aliases() do
    [
      validate: [
        "clean",
        "compile --warnings-as-error",
        "format --check-formatted",
        "credo",
        "dialyzer"
      ]
    ]
  end

  defp description() do
    """
    Geospatial feature storage for fast intersection checks
    """
  end

  defp package() do
    [
      files: ["lib/spatial_map.ex", "lib/spatial_map", "mix.exs", "README*"],
      maintainers: ["Powell Kinney"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/pkinney/spatial_map"}
    ]
  end
end
