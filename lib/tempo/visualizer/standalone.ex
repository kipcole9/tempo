defmodule Tempo.Visualizer.Standalone do
  @moduledoc """
  A helper that runs `Tempo.Visualizer` as a standalone web server
  for local exploration.

  Requires `:bandit` in your project's deps.

      Tempo.Visualizer.Standalone.start(port: 4001)
      # Visit http://localhost:4001

  Stop the server with `Tempo.Visualizer.Standalone.stop/1`,
  passing the PID returned from `start/1`.

  """

  @doc """
  Start the visualizer on the given port.

  ### Options

  * `:port` — TCP port to listen on. Default `4001`.

  * `:ip` — IP address to bind to. Default `:loopback` (only
    accessible from localhost). Pass `:any` to bind on all
    interfaces.

  ### Returns

  * `{:ok, pid}` on success.

  * `{:error, reason}` on failure — typically a port-in-use error.

  ### Examples

      iex> {:ok, _pid} = Tempo.Visualizer.Standalone.start(port: 4002)
      iex> _ = :timer.sleep(50)
      iex> :ok

  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(options \\ []) do
    ensure_bandit!()

    port = Keyword.get(options, :port, 4001)
    ip = Keyword.get(options, :ip, :loopback)

    bandit_options = [
      plug: Tempo.Visualizer,
      port: port,
      ip: ip_tuple(ip)
    ]

    Bandit.start_link(bandit_options)
  end

  @doc """
  Return a child specification suitable for embedding under a
  supervision tree.

  ### Options

  See `start/1`.

  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options \\ []) do
    ensure_bandit!()

    port = Keyword.get(options, :port, 4001)
    ip = Keyword.get(options, :ip, :loopback)

    %{
      id: __MODULE__,
      start: {Bandit, :start_link, [[plug: Tempo.Visualizer, port: port, ip: ip_tuple(ip)]]},
      type: :supervisor
    }
  end

  @doc """
  Stop a standalone server started by `start/1`.

  ### Arguments

  * `pid` — the process identifier returned by `start/1`.

  ### Returns

  * `:ok`.

  """
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    _ = Supervisor.stop(pid)
    :ok
  end

  ## Helpers

  defp ensure_bandit! do
    unless Code.ensure_loaded?(Bandit) do
      raise """
      Tempo.Visualizer.Standalone requires :bandit.
      Add `{:bandit, "~> 1.5"}` to your project's deps and run mix deps.get.
      """
    end
  end

  defp ip_tuple(:loopback), do: {127, 0, 0, 1}
  defp ip_tuple(:any), do: {0, 0, 0, 0}
  defp ip_tuple({_, _, _, _} = tuple), do: tuple
end
