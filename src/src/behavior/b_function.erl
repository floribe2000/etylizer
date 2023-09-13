-module(b_function).

-type ty_function() :: term().
-type ty_ref() :: {ty_ref, integer()}.

-callback function(ty_ref(), ty_ref()) -> ty_function().
-callback domain(ty_function()) -> ty_ref().
-callback codomain(ty_function()) -> ty_ref().

