defmodule Absinthe.Federation.Middleware do
  alias Absinthe.Blueprint.Schema.{FieldDefinition, InputValueDefinition}
  alias Absinthe.Blueprint.TypeReference.List, as: ListType
  alias Absinthe.Blueprint.TypeReference.Name
  alias Absinthe.Blueprint.TypeReference.NonNull
  alias Absinthe.Schema.Notation

  def call(%{state: :unresolved} = res, args) do
    # IO.puts("ARGS #{inspect(res.definition)}")
    # IO.inspect(res.definition)
    # definition = res.definition
    # IO.puts("SELECTIONS")
    # # IO.inspect(definition.selections)
    # IO.puts("END SELECTIONS")

    # selections =
    #   definition.selections
    #   |> Enum.map(fn s ->
    #     Map.get(s, :selections)
    #     |> Enum.map(fn inner ->
    #       inner
    #       |> Map.get(:name)
    #     end)
    #   end)
    #   |> List.flatten()

    # |> IO.inspect()

    # arguments = definition.argument_data

    # queries =
    #   Map.get(arguments, :representations)
    #   |> Enum.map(fn query ->
    #     {
    #       Absinthe.Federation.Schema.EntityUnion.resolve_type(query, res),
    #       Map.delete(query, "__typename")
    #     }
    #   end)

    # |> IO.inspect()

    # {_, q} = queries |> List.first()
    resolver_func = args |> List.first()

    field_def = %FieldDefinition{
      __reference__: Notation.build_reference(__ENV__),
      description: "",
      identifier: :_product,
      module: __MODULE__,
      name: "_product",
      type: %NonNull{
        of_type: %ListType{
          of_type: %Name{
            name: "Product"
          }
        }
      },
      middleware: [{Absinthe.Resolution, resolver_func}],
      arguments: build_arguments()
    }

    bp = res.schema.__absinthe_blueprint__()

    update_in(
      bp,
      [
        Access.key(:schema_definitions),
        Access.at(0),
        Access.key(:type_definitions),
        Access.filter(fn t ->
          Map.get(t, :name) == "RootQueryType"
        end),
        Access.key(:fields)
      ],
      fn fields ->
        fields ++ [field_def]
      end
    )

    # {:ok, phase} =
    # Absinthe.Phase.Parse.run("""
    #     query{
    #       product(upc:"123"){
    #         #{selections |> Enum.join("\n")}
    #       }
    #     }
    # """)
    # |> IO.inspect()

    # bp = res.schema.__absinthe_blueprint__()

    # type = res.parent_type

    pipeline =
      Absinthe.Pipeline.for_document(res.schema)
      |> IO.inspect()

    Absinthe.Pipeline.run(
      """
      query{
         query{
           product(upc:"123"){
            upc
            apa
           }
         }
      }
      """,
      pipeline
    )

    # result =
    #   queries
    #   |> Enum.map(fn {t, q} ->
    #     id = Map.get(q, "upc")

    #     {:ok, bp, _} =
    #       Absinthe.Pipeline.run(
    #         """
    #           query{
    #             #{t}(upc:"#{id}"){
    #               #{selections |> Enum.join("\n")}
    #             }
    #           }
    #         """,
    #         pipeline
    #       )

    #     bp.result
    #   end)
    #   |> Enum.map(fn res ->
    #     case res do
    #       %{data: %{"product" => r}} ->
    #         Map.put(r, "__typename", "Product")
    #         |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    #       _ ->
    #         res
    #     end
    #   end)

    # |> IO.inspect()

    # Absinthe.Pipeline.run(
    #   """
    #     query{
    #       product(upc:"123"){
    #         #{selections |> Enum.join("\n")}
    #       }
    #     }
    #   """,
    #   pipeline
    # )
    # Absinthe.Pipeline.run_phase(pipeline, phase)
    # |> IO.inspect()

    IO.puts("RUN PHASE")

    %{res | state: :resolved}
    # res
    # |> Absinthe.Resolution.put_result({:ok, result})

    # |> IO.inspect()
  end

  defp build_arguments(), do: [build_argument()]

  defp build_argument(),
    do: %InputValueDefinition{
      __reference__: Notation.build_reference(__ENV__),
      identifier: :representations,
      module: __MODULE__,
      name: "representations",
      placement: :argument_definition,
      type: %NonNull{
        of_type: %ListType{
          of_type: %NonNull{
            of_type: %Name{
              name: "_Any"
            }
          }
        }
      }
    }
end
