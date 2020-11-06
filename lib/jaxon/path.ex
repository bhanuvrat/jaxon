defmodule Jaxon.Path do
  alias Jaxon.{ParseError, EncodeError}

  @moduledoc ~S"""
  Utility module for parsing and encoding JSON path expressions.
  """

  @type t :: [String.t() | :all | :root | integer]

  @doc ~S"""
  Encoding path expressions:

  ```
  iex> Jaxon.Path.encode([:root, "test", 0])
  {:ok, "$.test[0]"}
  ```

  ```
  iex> Jaxon.Path.encode([:root, "with space", "other", "more space", 0])
  {:ok, ~s($["with space"].other["more space"][0])}
  ```

  How to handle encode errors:

  ```
  iex> Jaxon.Path.encode([:root, :whoops, "test", 0])
  {:error, %Jaxon.EncodeError{message: "`:whoops` is not a valid JSON path segment"}}
  ```
  """
  @spec encode(t()) :: {:ok, String.t()} | {:error, String.t()}
  def encode(path) do
    case do_encode(path) do
      {:error, err} ->
        {:error, %EncodeError{message: err}}

      result ->
        {:ok, result}
    end
  end

  @doc ~S"""
  Parse path expressions:

  ```
  iex> Jaxon.Path.parse("$[*].pets[0]")
  {:ok, [:root, :all, "pets", 0]}

  iex> Jaxon.Path.parse(~s($["key with spaces"].pets[0]))
  {:ok, [:root, "key with spaces", "pets", 0]}
  ```

  How to handle parse errors;

  ```
  iex> Jaxon.Path.parse("$.\"test[x]")
  {:error, %Jaxon.ParseError{message: "Ending quote not found for string at `\"test[x]`"}}
  ```
  """
  @spec parse(String.t()) :: {:ok, t} | {:error, String.t()}
  def parse(bin) do
    case parse_json_path(bin, "", []) do
      {:error, err} ->
        {:error, %ParseError{message: err}}

      result ->
        {:ok, result}
    end
  end

  @doc ~S"""
  Parse path expressions:

  ```
  iex> Jaxon.Path.parse!("$[*].pets[0]")
  [:root, :all, "pets", 0]
  ```
  """
  @spec parse!(String.t()) :: t() | no_return
  def parse!(bin) do
    case parse(bin) do
      {:error, err} ->
        raise err

      {:ok, path} ->
        path
    end
  end

  @spec encode!(t()) :: String.t() | no_return
  def encode!(path) do
    case encode(path) do
      {:error, err} ->
        raise err

      {:ok, result} ->
        result
    end
  end

  defp add_key(_, acc = {:error, _}) do
    acc
  end

  defp add_key("*", acc) do
    [:all | acc]
  end

  defp add_key("$", acc) do
    [:root | acc]
  end

  defp add_key(k, acc) do
    [k | acc]
  end

  defp parse_string(endchar, <<?\\, endchar, rest::binary>>, str) do
    parse_string(endchar, rest, <<str::binary, endchar>>)
  end

  defp parse_string(endchar, <<endchar, rest::binary>>, str) do
    {str, rest}
  end

  defp parse_string(_, "", _) do
    ""
  end

  defp parse_string(endchar, <<c, rest::binary>>, str) do
    parse_string(endchar, rest, <<str::binary, c>>)
  end

  defp parse_json_path(<<?\\, ?., rest::binary>>, cur, acc) do
    parse_json_path(rest, <<cur::binary, ?.>>, acc)
  end

  defp parse_json_path(<<?., rest::binary>>, "", acc) do
    parse_json_path(rest, "", acc)
  end

  defp parse_json_path(<<"[*]", rest::binary>>, "", acc) do
    [:all | parse_json_path(rest, "", acc)]
  end

  defp parse_json_path(bin = <<?[, ?", rest::binary>>, "", acc) do
    case parse_string(?", rest, "") do
      {key, <<?], rest::binary>>} ->
        [key | parse_json_path(rest, "", acc)]

      {_, _} ->
        {:error, "Ending bracket not found for string at `#{String.slice(bin, 0, 10)}`"}

      "" ->
        {:error, "Ending quote not found for string at `#{String.slice(bin, 0, 10)}`"}
    end
  end

  defp parse_json_path(bin = <<?[, rest::binary>>, "", acc) do
    case Integer.parse(rest) do
      {i, <<?], rest::binary>>} ->
        [i | parse_json_path(rest, "", acc)]

      _ ->
        case parse_string(?], rest, "") do
          {key, rest} ->
            [key | parse_json_path(rest, "", acc)]

          _ ->
            {:error, "Ending bracket not found for string at `#{String.slice(bin, 0, 10)}`"}
        end
    end
  end

  defp parse_json_path(rest = <<?[, _::binary>>, cur, acc) do
    add_key(cur, parse_json_path(rest, "", acc))
  end

  defp parse_json_path(<<?., rest::binary>>, cur, acc) do
    add_key(cur, parse_json_path(rest, "", acc))
  end

  defp parse_json_path("", "", _) do
    []
  end

  defp parse_json_path("", cur, acc) do
    add_key(cur, acc)
  end

  defp parse_json_path(bin = <<?", rest::binary>>, "", acc) do
    case parse_string(?", rest, "") do
      {key, rest} ->
        [key | parse_json_path(rest, "", acc)]

      _ ->
        {:error, "Ending quote not found for string at `#{String.slice(bin, 0, 10)}`"}
    end
  end

  defp parse_json_path(<<c, rest::binary>>, cur, acc) do
    parse_json_path(rest, <<cur::binary, c>>, acc)
  end

  defp append_segment(err = {:error, _}, _) do
    err
  end

  defp append_segment(_, err = {:error, _}) do
    err
  end

  defp append_segment(s, rest = "[" <> _) do
    s <> rest
  end

  defp append_segment(s, "") do
    s
  end

  defp append_segment(s, rest) do
    s <> "." <> rest
  end

  defp do_encode_segment(:root) do
    "$"
  end

  defp do_encode_segment(:all) do
    "[*]"
  end

  defp do_encode_segment(i) when is_integer(i) do
    "[#{i}]"
  end

  defp do_encode_segment("") do
    ~s([])
  end

  defp do_encode_segment(s) when is_binary(s) do
    if(String.contains?(s, ["*", "$", "]", "[", ".", "\"", " "])) do
      safe_str =
        String.replace(s, "\"", "\\\"")

      ~s(["#{safe_str}"])
    else
      s
    end
  end

  defp do_encode_segment(s) do
    {:error, "`#{inspect(s)}` is not a valid JSON path segment"}
  end

  defp do_encode([]) do
    ""
  end

  defp do_encode([h | t]) do
    append_segment(do_encode_segment(h), do_encode(t))
  end
end
