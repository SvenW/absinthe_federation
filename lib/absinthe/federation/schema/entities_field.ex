defmodule Absinthe.Federation.Schema.EntitiesField do
  @moduledoc false

  alias Absinthe.{Blueprint, Type}
  alias Blueprint.Result
  alias Absinthe.Blueprint.Schema.FieldDefinition
  alias Absinthe.Blueprint.Schema.InputValueDefinition
  alias Absinthe.Blueprint.TypeReference.List, as: ListType
  alias Absinthe.Blueprint.TypeReference.Name
  alias Absinthe.Blueprint.TypeReference.NonNull
  alias Absinthe.Schema.Notation

  # TODO: Fix __reference__ typespec upstream in absinthe
  @type input_value_definition :: %InputValueDefinition{
          name: String.t(),
          description: nil | String.t(),
          type: Blueprint.TypeReference.t(),
          default_value: nil | Blueprint.Input.t(),
          default_value_blueprint: Blueprint.Draft.t(),
          directives: [Blueprint.Directive.t()],
          source_location: nil | Blueprint.SourceLocation.t(),
          # The struct module of the parent
          placement: :argument_definition | :input_field_definition,
          # Added by phases
          flags: Blueprint.flags_t(),
          errors: [Absinthe.Phase.Error.t()],
          __reference__: nil | map()
        }

  @type field_definition :: %FieldDefinition{
          name: String.t(),
          identifier: atom,
          description: nil | String.t(),
          deprecation: nil | Blueprint.Schema.Deprecation.t(),
          arguments: [input_value_definition()],
          type: Blueprint.TypeReference.t(),
          directives: [Blueprint.Directive.t()],
          source_location: nil | Blueprint.SourceLocation.t(),
          # Added by DSL
          description: nil | String.t(),
          middleware: [any],
          # Added by phases
          flags: Blueprint.flags_t(),
          errors: [Absinthe.Phase.Error.t()],
          triggers: [],
          module: nil | module(),
          function_ref: nil | function(),
          default_value: nil | any(),
          config: nil,
          complexity: nil,
          __reference__: nil | map(),
          __private__: []
        }

  @spec build() :: field_definition()
  def build() do
    %FieldDefinition{
      __reference__: Notation.build_reference(__ENV__),
      description: """
      Returns a non-nullable list of _Entity types
      and have a single argument with an argument name of representations
      and type [_Any!]! (non-nullable list of non-nullable _Any scalars).
      The _entities field on the query root must allow a list of _Any scalars
      which are "representations" of entities from external services.
      These representations should be validated with the following rules:

      - Any representation without a __typename: String field is invalid.
      - Representations must contain at least the fields defined in the fieldset of a @key directive on the base type.
      """,
      identifier: :_entities,
      module: __MODULE__,
      name: "_entities",
      type: %NonNull{
        of_type: %ListType{
          of_type: %Name{
            name: "_Entity"
          }
        }
      },
      middleware: [__MODULE__],
      arguments: build_arguments()
    }
  end

  def call(%{state: :unresolved} = res, _args) do
    resolutions = resolver(res.source, res.arguments, res)

    # value = Enum.map(resolutions, fn r -> r.value end)

    operation = resolutions |> List.first()

    exec = Absinthe.Blueprint.Execution.get(operation.schema.__absinthe_blueprint__(), operation)
    # op = Absinthe.Blueprint.current_operation(res.schema.__absinthe_blueprint__())
    IO.puts("OPERATION #{inspect(operation.schema.__absinthe_blueprint__())}")
    plugins = operation.schema.plugins()
    exec = plugins |> run_callbacks(:before_resolution, exec, true)
    # common = Map.take(exec, [:adapter, :context, :acc, :root_value, :schema, :fragments, :fields_cache])

    # resolution =
    #   %Absinthe.Resolution{
    #     path: nil,
    #     source: nil,
    #     parent_type: nil,
    #     middleware: nil,
    #     definition: nil,
    #     arguments: nil
    #   }
    #   |> Map.merge(common)

    # IO.puts("EXEC #{inspect(exec.result)}")
    # IO.puts("EXEC KEYS #{inspect(Map.keys(exec.result))}")

    # exec.result
    # |> Absinthe.Phase.Document.Execution.Resolution.walk_result(operation, res.source, resolution, [
    #   operation
    # ])
    IO.puts("WALK RESULT")

    {result, operation} =
      Absinthe.Phase.Document.Execution.Resolution.walk_result(
        operation,
        res.definition,
        res.parent_type,
        res,
        []
      )
      |> propagate_null_trimming

    # exec = update_persisted_fields(exec, operation)
    exec = plugins |> run_callbacks(:after_resolution, exec, true)

    exec = %{exec | result: result}

    blueprint = %{operation.schema.__absinthe_blueprint__() | execution: exec}

    IO.puts("BLUEPRINT #{inspect(blueprint.execution)}")

    v =
      operation.schema.plugins()
      |> Absinthe.Plugin.pipeline(exec)
      |> IO.inspect()

    Absinthe.Phase.Document.Result.run(blueprint)
    |> IO.inspect()

    IO.puts("WALKED RESULT")

    %{
      res
      | state: :resolved,
        value: v
    }
  end

  # defp update_persisted_fields(dest, %{acc: acc, context: context, fields_cache: cache}) do
  #   %{dest | acc: acc, context: context, fields_cache: cache}
  # end

  defp run_callbacks(plugins, callback, acc, true) do
    Enum.reduce(plugins, acc, &apply(&1, callback, [&2]))
  end

  defp run_callbacks(_, _, acc, _), do: acc

  defp propagate_null_trimming({%{values: values} = node, res}) do
    values = Enum.map(values, &do_propagate_null_trimming/1)
    node = %{node | values: values}
    {do_propagate_null_trimming(node), res}
  end

  defp propagate_null_trimming({node, res}) do
    {do_propagate_null_trimming(node), res}
  end

  defp do_propagate_null_trimming(node) do
    if bad_child = find_bad_child(node) do
      bp_field = node.emitter

      full_type =
        with %{type: type} <- bp_field.schema_node do
          type
        end

      nil
      |> to_result(bp_field, full_type, node.extensions)
      |> Map.put(:errors, bad_child.errors)

      # ^ We don't have to worry about clobbering the current node's errors because,
      # if it had any errors, it wouldn't have any children and we wouldn't be
      # here anyway.
    else
      node
    end
  end

  defp to_result(nil, blueprint, _, extensions) do
    %Result.Leaf{emitter: blueprint, value: nil, extensions: extensions}
  end

  defp to_result(root_value, blueprint, %Absinthe.Type.NonNull{of_type: inner_type}, extensions) do
    to_result(root_value, blueprint, inner_type, extensions)
  end

  defp to_result(root_value, blueprint, %Absinthe.Type.Object{}, extensions) do
    %Result.Object{root_value: root_value, emitter: blueprint, extensions: extensions}
  end

  defp to_result(root_value, blueprint, %Absinthe.Type.Interface{}, extensions) do
    %Result.Object{root_value: root_value, emitter: blueprint, extensions: extensions}
  end

  defp to_result(root_value, blueprint, %Type.Union{}, extensions) do
    %Result.Object{root_value: root_value, emitter: blueprint, extensions: extensions}
  end

  defp to_result(root_value, blueprint, %Type.List{of_type: inner_type}, extensions) do
    values =
      root_value
      |> List.wrap()
      |> Enum.map(&to_result(&1, blueprint, inner_type, extensions))

    %Result.List{values: values, emitter: blueprint, extensions: extensions}
  end

  defp to_result(root_value, blueprint, %Type.Scalar{}, extensions) do
    %Result.Leaf{
      emitter: blueprint,
      value: root_value,
      extensions: extensions
    }
  end

  defp to_result(root_value, blueprint, %Type.Enum{}, extensions) do
    %Result.Leaf{
      emitter: blueprint,
      value: root_value,
      extensions: extensions
    }
  end

  defp find_bad_child(%{fields: fields}) do
    Enum.find(fields, &non_null_violation?/1)
  end

  defp find_bad_child(%{values: values}) do
    Enum.find(values, &non_null_list_violation?/1)
  end

  defp find_bad_child(_) do
    false
  end

  defp non_null_violation?(%{value: nil, emitter: %{schema_node: %{type: %Absinthe.Type.NonNull{}}}}) do
    true
  end

  defp non_null_violation?(_) do
    false
  end

  # FIXME: Not super happy with this lookup process.
  # Also it would be nice if we could use the same function as above.
  defp non_null_list_violation?(%{
         value: nil,
         emitter: %{schema_node: %{type: %Absinthe.Type.List{of_type: %Absinthe.Type.NonNull{}}}}
       }) do
    true
  end

  defp non_null_list_violation?(%{
         value: nil,
         emitter: %{
           schema_node: %{type: %Absinthe.Type.NonNull{of_type: %Absinthe.Type.List{of_type: %Absinthe.Type.NonNull{}}}}
         }
       }) do
    true
  end

  defp non_null_list_violation?(_) do
    false
  end

  def resolver(parent, %{representations: representations}, resolution) do
    Enum.map(representations, &entity_accumulator(&1, parent, resolution))
    |> Enum.map(fn {_, res} ->
      # res = Absinthe.Resolution.call(resolution, fun)
      # pipeline = Absinthe.Pipeline.for_schema(res.schema)
      # IO.puts("HEJEJEJEJ")
      # phase = Absinthe.Phase.Schema.InlineFunctions.inline_functions(res.source, res.schema, []) |> IO.inspect()
      # IO.puts("HEJEJEJEJ")
      # Absinthe.Pipeline.run_phase(pipeline, phase) |> IO.inspect()
      res
    end)
  end

  defp entity_accumulator(representation, parent, %{schema: schema} = resolution) do
    typename = Map.get(representation, "__typename")

    {Absinthe.Resolution,
     schema
     |> Absinthe.Schema.lookup_type(typename)
     |> resolve_representation(parent, representation, resolution)}
  end

  defp resolve_representation(
         %struct_type{fields: fields},
         parent,
         representation,
         resolution
       )
       when struct_type in [Absinthe.Type.Object, Absinthe.Type.Interface],
       do: resolve_reference(fields[:_resolve_reference], parent, representation, resolution)

  defp resolve_representation(_schema_type, _parent, representation, _schema),
    do:
      {:error,
       "The _entities resolver tried to load an entity for type '#{Map.get(representation, "__typename")}', but no object type of that name was found in the schema"}

  defp resolve_reference(nil, _parent, representation, _resolution), do: {:ok, representation}

  defp resolve_reference(%{middleware: middleware}, _parent, representation, %{schema: schema} = resolution) do
    args = for {key, val} <- representation, into: %{}, do: {String.to_atom(key), val}

    middleware
    |> Absinthe.Middleware.unshim(schema)
    |> Enum.filter(&only_resolver_middleware/1)
    |> List.first()
    |> case do
      {_, resolve_ref_func} when is_function(resolve_ref_func, 2) ->
        # fn _, _ -> resolve_ref_func.(args, resolution) end
        Absinthe.Resolution.call(%{resolution | arguments: args}, resolve_ref_func)

      {_, resolve_ref_func} when is_function(resolve_ref_func, 3) ->
        # fn _, _ -> resolve_ref_func.(parent, args, resolution) end
        Absinthe.Resolution.call(%{resolution | arguments: args}, resolve_ref_func)

      _ ->
        {:ok, representation}
    end
  end

  defp only_resolver_middleware({{Absinthe.Resolution, :call}, _}), do: true

  defp only_resolver_middleware(_), do: false

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
