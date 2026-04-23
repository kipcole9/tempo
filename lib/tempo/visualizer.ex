if Code.ensure_loaded?(Plug.Router) and Code.ensure_loaded?(Bandit) do
  defmodule Tempo.Visualizer do
    @moduledoc """
    A web-based visualizer for ISO 8601 / ISO 8601-2 / IXDTF strings.

    This module is a `Plug.Router` that can be mounted inside a
    Phoenix or Plug application, or run standalone during development
    via `Tempo.Visualizer.Standalone`.

    ## What it does

    Enter any ISO 8601, ISO 8601-2 (EDTF), or IXDTF string into the
    top input. The page renders a visual breakdown:

    * The input echoed in large monospace.

    * Each parsed component as its own box (year, month, day, hour,
      time zone, qualification, IXDTF suffix, …) with the canonical
      glyph above a short description.

    * A details card showing every field of the parsed
      `%Tempo{}` / `%Tempo.Interval{}` / `%Tempo.Duration{}` /
      `%Tempo.Set{}` struct.

    All state lives in the URL — share a link, share a parse.

    ## Mounting in Phoenix / Plug

        forward "/visualize", Tempo.Visualizer

    ## Running standalone

        Tempo.Visualizer.Standalone.start(port: 4001)
        # Visit http://localhost:4001

    ## Optional dependencies

    The visualizer requires **both** `:plug` and `:bandit`. Both are
    declared `optional: true` in Tempo's `mix.exs`:

        {:plug, "~> 1.15"},
        {:bandit, "~> 1.5"}

    The module is compiled only when both are available at build time.
    The core parser has no such dependency and will compile without
    either in place.

    """

    use Plug.Router

    plug(:match)
    plug(Plug.Parsers, parsers: [:urlencoded], pass: ["text/*"])
    plug(:dispatch)

    alias Tempo.Visualizer.Assets
    alias Tempo.Visualizer.ParseView

    get "/" do
      params = %{input: Map.get(conn.params, "iso", "")}
      html(conn, ParseView.render(params, base_path(conn)))
    end

    get "/assets/style.css" do
      conn
      |> Plug.Conn.put_resp_content_type("text/css")
      |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> Plug.Conn.send_resp(200, Assets.css())
    end

    match _ do
      send_resp(conn, 404, "Not found")
    end

    ## Helpers

    defp html(conn, iodata) do
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, IO.iodata_to_binary(iodata))
    end

    # When mounted via `forward "/visualize", ...`, Plug sets
    # script_name. Rebuild the base URL from it so link hrefs
    # resolve correctly whether mounted at / or at /visualize.
    defp base_path(%Plug.Conn{script_name: []}), do: ""
    defp base_path(%Plug.Conn{script_name: segments}), do: "/" <> Enum.join(segments, "/")
  end
else
  defmodule Tempo.Visualizer do
    @moduledoc """
    Stub for `Tempo.Visualizer` — compiled when the optional
    `:plug` and `:bandit` dependencies are not available.

    Mounting this stub raises a clear error pointing at the
    missing dependencies.
    """

    @compile_error "Tempo.Visualizer requires both :plug and :bandit. " <>
                     "Add `{:plug, \"~> 1.15\"}` and `{:bandit, \"~> 1.5\"}` " <>
                     "to your project's deps and run `mix deps.get`."

    @doc false
    def init(_), do: raise(@compile_error)

    @doc false
    def call(_, _), do: raise(@compile_error)
  end
end
