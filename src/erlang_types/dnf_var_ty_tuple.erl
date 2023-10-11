-module(dnf_var_ty_tuple).

-define(P, {dnf_ty_tuple, ty_variable}).
-define(F(Z), fun() -> Z end).


-export([equal/2, compare/2]).

%% %TODO parameterize over size too
-export([empty/0, any/0, union/2, intersect/2, diff/2, negate/1]).
-export([is_any/1, normalize/4, substitute/4]).

-export([var/1, tuple/1, all_variables/1, has_ref/2, transform/2, is_empty/1]).

-type dnf_tuple() :: term().
-type ty_tuple() :: dnf_tuple(). % ty_tuple:type()
-type variable() :: term(). % variable:type()
-type dnf_var_tuple() :: term().

-spec tuple(ty_tuple()) -> dnf_var_tuple().
tuple(Tuple) -> gen_bdd:terminal(?P, Tuple).

-spec var(variable()) -> dnf_var_tuple().
var(Var) -> gen_bdd:element(?P, Var).

% ==
% type interface
% ==
empty() -> gen_bdd:empty(?P).
any() -> gen_bdd:any(?P).

union(B1, B2) -> gen_bdd:union(?P, B1, B2).
intersect(B1, B2) -> gen_bdd:intersect(?P, B1, B2).
diff(B1, B2) -> gen_bdd:diff(?P, B1, B2).
negate(B1) -> gen_bdd:negate(?P, B1).

is_any(B) -> gen_bdd:is_any(?P, B).
is_empty(TyBDD) -> gen_bdd:dnf(?P, TyBDD, {fun is_empty_coclause/3, fun gen_bdd:is_empty_union/2}).
is_empty_coclause(_Pos, _Neg, T) -> dnf_ty_tuple:is_empty(T).

% ==
% basic interface
% ==

equal(B1, B2) -> gen_bdd:equal(?P, B1, B2).
compare(B1, B2) -> gen_bdd:compare(?P, B1, B2).

normalize(Size, Ty, Fixed, M) ->
  normalize(Size, Ty, [], [], Fixed, M).

normalize(_, {terminal, 0}, _, _, _, _) -> [[]]; % satisfiable
normalize(Size, {terminal, Tuple}, PVar, NVar, Fixed, M) ->
  case ty_ref:is_normalized_memoized(Tuple, Fixed, M) of
    true ->
      % TODO test case
      error({todo, extract_test_case, memoize_function}); %[[]];
    miss ->
      % memoize only non-variable component t0
      dnf_ty_tuple:normalize(Size, Tuple, PVar, NVar, Fixed, sets:union(M, sets:from_list([Tuple])))
  end;
normalize(Size, {node, Variable, PositiveEdge, NegativeEdge}, PVar, NVar, Fixed, M) ->
  constraint_set:meet(
    ?F(normalize(Size, PositiveEdge, [Variable | PVar], NVar, Fixed, M)),
    ?F(normalize(Size, NegativeEdge, PVar, [Variable | NVar], Fixed, M))
  ).

substitute(Size, T, M, Memo) -> substitute(Size, T, M, Memo, [], []).

substitute(default, {terminal, 0}, _, _, _, _) -> {empty(), #{}};
substitute(Size, {terminal, 0}, _, _, _, _) -> {empty(), #{Size => empty()}};
substitute(Size, {terminal, Tuple}, Map, Memo, Pos, Neg) ->
  AllPos = lists:map(
    fun(Var) ->
      Substitution = maps:get(Var, Map, ty_rec:variable(Var)),
      ty_rec:pi(tuple, Substitution)
    end, Pos),
  AllNeg = lists:map(
    fun(Var) ->
      Substitution = maps:get(Var, Map, ty_rec:variable(Var)),
      NewNeg = ty_rec:negate(Substitution),
      ty_rec:pi(tuple, NewNeg)
    end, Neg),

  Base = case Size of
           default ->
             {tuple(dnf_ty_tuple:substitute(Tuple, Map, Memo)), #{}};
           _ ->
             {empty(), #{Size => tuple(dnf_ty_tuple:substitute(Tuple, Map, Memo))}}
         end,
  lists:foldl(fun({CurrentDefault, CurrentTuple}, {AllDefault, AllTuple}) ->
    {intersect(CurrentDefault, AllDefault), mingle(CurrentDefault, AllDefault, CurrentTuple, AllTuple, fun intersect/2)}
              end, Base, AllPos ++ AllNeg);

substitute(Size, {node, Variable, PositiveEdge, NegativeEdge}, Map, Memo, P, N) ->
  {LeftDefault, LeftOthers} = substitute(Size, PositiveEdge, Map, Memo, [Variable | P], N),
  {RightDefault, RightOthers} = substitute(Size, NegativeEdge, Map, Memo, P, [Variable | N]),

  {union(LeftDefault, RightDefault), mingle(LeftDefault, RightDefault, LeftOthers, RightOthers, fun union/2)}.

has_ref({terminal, 0}, _) -> false;
has_ref({terminal, Tuple}, Ref) ->
  dnf_ty_tuple:has_ref(Tuple, Ref);
has_ref({node, _Variable, PositiveEdge, NegativeEdge}, Ref) ->
  has_ref(PositiveEdge, Ref) orelse has_ref(NegativeEdge, Ref).

all_variables({Default, Others}) when is_map(Others) ->
  all_variables(Default) ++ lists:map(fun({_K,V}) -> all_variables(V) end, maps:to_list(Others));
all_variables({terminal, 0}) -> [];
all_variables({terminal, Tuple}) -> dnf_ty_tuple:all_variables(Tuple);
all_variables({node, Variable, PositiveEdge, NegativeEdge}) ->
  [Variable] ++ all_variables(PositiveEdge) ++ all_variables(NegativeEdge).


mingle(LeftDefault, RightDefault, AllLeft, AllRight, Op) ->
  AllKeys = maps:keys(AllLeft) ++ maps:keys(AllRight),
  % LeftDefault + Right (left not assigned)  Left + RightDefault (right not assigned) Left + Right (both)
  maps:from_list(lists:map(fun(Key) -> {Key, Op(maps:get(Key, AllLeft, LeftDefault), maps:get(Key, AllRight, RightDefault))} end, AllKeys)).


transform({terminal, 0}, #{empty := E}) -> E();
transform({terminal, Tuple}, Ops) ->
  dnf_ty_tuple:transform(Tuple, Ops);
transform({node, Variable, PositiveEdge, NegativeEdge},
    Ops = #{negate := Negate, var := ToVar, union := Union, intersect := Intersect}) ->
  AstVar = ToVar(Variable),
  Union([
    Intersect([AstVar, transform(PositiveEdge, Ops)]),
    Intersect([Negate(AstVar), transform(NegativeEdge, Ops)])
  ]).

%%-ifdef(TEST).
%%-include_lib("eunit/include/eunit.hrl").
%%
%%usage_test() ->
%%  %   a1 ^ (int, int)
%%  TIa = ty_rec:interval(dnf_var_int:int(ty_interval:interval('*', '*'))),
%%  TIb = ty_rec:interval(dnf_var_int:int(ty_interval:interval('*', '*'))),
%%  Ty_Tuple = ty_tuple:tuple(TIa, TIb),
%%
%%  VarA = ty_variable:new("a1"),
%%
%%  Dnf_Ty_Tuple = dnf_ty_tuple:tuple(Ty_Tuple),
%%
%%  BVar1 = dnf_var_ty_tuple:var(VarA),
%%  BTupleA = dnf_var_ty_tuple:tuple(Dnf_Ty_Tuple),
%%
%%  Bdd = dnf_var_ty_tuple:intersect(BVar1, BTupleA),
%%
%%  false = dnf_var_int:is_empty(Bdd),
%%%%  io:format(user, "~p~n", [Bdd]),
%%
%%  ok.
%%
%%-endif.
