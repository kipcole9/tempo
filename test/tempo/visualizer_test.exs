defmodule Tempo.VisualizerTest do
  use ExUnit.Case, async: true

  alias Tempo.Visualizer

  describe "Plug router" do
    test "root with no input returns 200 and the empty card" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "Try an example"
      assert Plug.Conn.get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end

    test "root with a valid iso parses and renders segment boxes" do
      conn =
        :get
        |> Plug.Test.conn("/?iso=2022-06-15")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ ~s|<div class="vz-glyph">2022</div>|
      assert conn.resp_body =~ ~s|<div class="vz-glyph">-06</div>|
      assert conn.resp_body =~ ~s|<div class="vz-glyph">-15</div>|
      assert conn.resp_body =~ "June (month 6)"
    end

    test "root with a qualified date emits a qualification segment" do
      conn =
        :get
        |> Plug.Test.conn("/?iso=2022-06-15%3F")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "vz-segment--qualification"
    end

    test "root with an IXDTF suffix emits extended segments" do
      conn =
        :get
        |> Plug.Test.conn("/?iso=2022-06-15%5BEurope%2FParis%5D%5Bu-ca%3Dhebrew%5D")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "[Europe/Paris]"
      assert conn.resp_body =~ "[u-ca=hebrew]"
      assert conn.resp_body =~ "vz-segment--extended"
    end

    test "root with an invalid iso shows the error card" do
      conn =
        :get
        |> Plug.Test.conn("/?iso=bogus")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      assert conn.resp_body =~ "Parse error"
      assert conn.resp_body =~ "vz-error"
    end

    test "interval input is visualised with both endpoints" do
      conn =
        :get
        |> Plug.Test.conn("/?iso=1984%3F%2F2004~")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      # Two year segments
      assert Regex.scan(~r/"vz-label">Year</, conn.resp_body) |> length() == 2
      # Separator between them
      assert conn.resp_body =~ ~s|<div class="vz-glyph">/</div>|
    end

    test "style.css is served with caching headers" do
      conn =
        :get
        |> Plug.Test.conn("/assets/style.css")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") |> hd() =~ "text/css"
      assert Plug.Conn.get_resp_header(conn, "cache-control") |> hd() =~ "immutable"
      assert conn.resp_body =~ ".vz-segment"
    end

    test "unknown path returns 404" do
      conn =
        :get
        |> Plug.Test.conn("/does-not-exist")
        |> Visualizer.call(Visualizer.init([]))

      assert conn.status == 404
    end
  end

  describe "ParseView" do
    test "renders a season expanded to an interval" do
      # Tempo expands astronomical seasons (code 25 → Northern
      # spring) to a concrete equinox/solstice-bounded interval
      # at parse time, so the visualisation shows the interval
      # rather than the bare "25" month code.
      html =
        %{input: "2022-25"}
        |> Tempo.Visualizer.ParseView.render("")
        |> IO.iodata_to_binary()

      # March equinox → June solstice of 2022
      assert html =~ "Tempo.Interval"
      assert html =~ "2022Y3M20D"
      assert html =~ "2022Y6M21D"
    end

    test "renders unspecified digits as a mask glyph" do
      html =
        %{input: "156X"}
        |> Tempo.Visualizer.ParseView.render("")
        |> IO.iodata_to_binary()

      assert html =~ ~s|<div class="vz-glyph">156X</div>|
      assert html =~ "unspecified digits"
    end

    test "renders a negative year with its sign" do
      html =
        %{input: "-1XXX-XX"}
        |> Tempo.Visualizer.ParseView.render("")
        |> IO.iodata_to_binary()

      assert html =~ "-1XXX"
    end

    test "renders open-ended interval segment" do
      html =
        %{input: "1985/.."}
        |> Tempo.Visualizer.ParseView.render("")
        |> IO.iodata_to_binary()

      assert html =~ "Undefined endpoint"
    end
  end
end
