defmodule Hex.Config do
  def read do
    case File.read(config_path()) do
      {:ok, binary} ->
        {:ok, term} = decode_term(binary)
        term
      {:error, _} ->
        []
    end
  end

  def update(config) do
    read()
    |> Keyword.merge(config)
    |> write()
  end

  def remove(keys) do
    read()
    |> Keyword.drop(keys)
    |> write()
  end

  def write(config) do
    string = encode_term(config)

    path = config_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, string)
  end

  defp config_path do
    Path.join(hex_home(), "hex.config")
  end

  defp hex_home do
    if Process.whereis(Hex.State) do
      Hex.State.fetch!(:home)
    else
      Path.expand(System.get_env("HEX_HOME") || "~/.hex")
    end
  end

  defp encode_term(list) do
    list
    |> Enum.map(&[:io_lib.print(&1) | ".\n"])
    |> IO.iodata_to_binary
  end

  defp decode_term(string) do
    {:ok, pid} = StringIO.open(string)
    try do
      consult(pid, [], string)
    after
      StringIO.close(pid)
    end
  end

  defp consult(pid, acc, string) when is_pid(pid) do
    case :io.read(pid, '') do
      {:ok, term}      -> consult(pid, [term|acc], string)
      {:error, reason} -> {:error, reason}
      :error           -> IO.inspect(string, limit: :infinity); :error
      :eof             -> {:ok, Enum.reverse(acc)}
    end
  end
end
