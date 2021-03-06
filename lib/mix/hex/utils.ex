defmodule Mix.Hex.Utils do
  @apikey_tag "HEXAPIKEY"

  def table(header, values) do
    header = Enum.map(header, &[:underline, &1])
    widths = widths([header|values])

    print_row(header, widths)
    Enum.each(values, &print_row(&1, widths))
  end

  defp ansi_length(binary) when is_binary(binary),
    do: byte_size(binary)
  defp ansi_length(list) when is_list(list),
    do: Enum.reduce(list, 0, &(ansi_length(&1) + &2))
  defp ansi_length(atom) when is_atom(atom),
    do: 0

  defp print_row(strings, widths) do
    Enum.map(Enum.zip(strings, widths), fn {string, width} ->
      pad_size = width-ansi_length(string)+2
      pad = :lists.duplicate(pad_size, ?\s)
      [string, :reset, pad]
    end)
    |> IO.ANSI.format
    |> Hex.Shell.info
  end

  defp widths([head|tail]) do
    widths = Enum.map(head, &ansi_length/1)

    Enum.reduce(tail, widths, fn list, acc ->
      Enum.zip(list, acc)
      |> Enum.map(fn {string, width} -> max(width, ansi_length(string)) end)
    end)
  end

  def generate_key(username, password) do
    Hex.Shell.info("Generating API key...")
    {:ok, name} = :inet.gethostname()
    name = List.to_string(name)

    case Hex.API.Key.new(name, [user: username, pass: password]) do
      {201, body, _} ->
        Hex.Shell.info("Encrypting API key with password...")
        salt = Hex.Crypto.gen_salt()
        cipher = Hex.Crypto.encrypt(password, salt, body["secret"], @apikey_tag)
        Hex.Config.update([
          username: username,
          key_cipher: Base.encode16(cipher, case: :lower),
          key_salt: Base.encode16(salt, case: :lower)])

      {code, body, _} ->
        Mix.shell.error("Generation of API key failed (#{code})")
        Hex.Utils.print_error_result(code, body)
    end
  end

  def auth_info(config) do
    key = config[:key]
    cipher = config[:key_cipher]
    salt = config[:key_salt]

    cond do
      cipher && salt ->
        cipher = Base.decode16!(cipher, case: :lower)
        salt = Base.decode16!(salt, case: :lower)
        [key: decrypt_key(cipher, salt)]
      key ->
        encrypt_key(config, key)
        [key: key]
      true ->
        Mix.raise "No authorized user found. Run 'mix hex.user auth'"
    end
  end

  defp encrypt_key(config, key) do
    Hex.Shell.info("Your stored API key is not encrypted, please supply a password to encrypt it")

    password = password_get("Password:") |> String.strip
    confirm = password_get("Password (confirm):") |> String.strip
    if password != confirm do
      Mix.raise "Entered passwords do not match"
    end

    salt = Hex.Crypto.gen_salt()
    cipher = Hex.Crypto.encrypt(password, salt, key, @apikey_tag)
             |> Base.encode16(case: :lower)
    salt = Base.encode16(salt, case: :lower)

    config
    |> Keyword.delete(:key)
    |> Keyword.merge([key_cipher: cipher, key_salt: salt])
    |> Hex.Config.write
  end

  defp decrypt_key(cipher, salt) do
    password = password_get("Password:") |> String.strip
    case Hex.Crypto.decrypt(password, salt, cipher, @apikey_tag) do
      {:ok, key} ->
        key
      :error ->
        Mix.raise "Wrong password"
    end
  end

  def generate_key_cipher(password, key) do
    salt = Hex.Crypto.gen_salt()
    cipher = Hex.Crypto.encrypt(password, salt, key, @apikey_tag)
    [key_cipher: Base.encode16(cipher, case: :lower),
     key_salt: Base.encode16(salt, case: :lower)]
  end

  def persist_key(password, key) do
    generate_key_cipher(password, key)
    |> Hex.Config.update
  end

  def required_opts(opts, required) do
    Enum.map(required, fn req ->
      unless Keyword.has_key?(opts, req) do
        Mix.raise "Missing command line option: #{req}"
      end
    end)
  end

  # Password prompt that hides input by every 1ms
  # clearing the line with stderr
  def password_get(prompt) do
    if Hex.State.fetch!(:clean_pass) do
      password_clean(prompt)
    else
      Hex.Shell.prompt(prompt <> " ")
    end
  end

  defp password_clean(prompt) do
    pid   = spawn_link(fn -> loop(prompt) end)
    ref   = make_ref()
    value = IO.gets(prompt <> " ")

    send pid, {:done, self(), ref}
    receive do: ({:done, ^pid, ^ref}  -> :ok)

    value
  end

  defp loop(prompt) do
    receive do
      {:done, parent, ref} ->
        send parent, {:done, self(), ref}
        IO.write(:standard_error, "\e[2K\r")
    after
      1 ->
        IO.write(:standard_error, "\e[2K\r#{prompt} ")
        loop(prompt)
    end
  end

  @progress_steps 25

  def progress(nil) do
    fn _ -> nil end
  end

  def progress(max) do
    put_progress(0, 0)

    fn size ->
      fraction = size / max
      completed = trunc(fraction * @progress_steps)
      put_progress(completed, trunc(fraction * 100))
      size
    end
  end

  defp put_progress(completed, percent) do
    unfilled = @progress_steps - completed
    str = "\r[#{String.duplicate("#", completed)}#{String.duplicate(" ", unfilled)}]"
    IO.write(:stderr, str <> " #{percent}%")
  end

  def clean_version("v" <> version), do: version
  def clean_version(version),        do: version
end
