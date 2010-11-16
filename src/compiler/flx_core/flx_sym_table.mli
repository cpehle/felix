(** The type of the (raw, unbound) symbol table. *)
type t

(** quick debugging info *)
val summary: t -> string
val detail: t -> string

(** Construct a symbol table. *)
val create : unit -> t

(** Adds the symbol with the bound index to the symbol table. *)
val add : t -> Flx_types.bid_t -> Flx_types.bid_t option -> Flx_sym.t -> unit

(** Returns if the bound index is in the symbol table. *)
val mem : t -> Flx_types.bid_t -> bool

(** Searches the symbol table for the given symbol. Raises Not_found if the
 * index is not in the symbol table. *)
val find : t -> Flx_types.bid_t -> Flx_sym.t

(** find string name by index, raises Not_found if missing  *)
val find_id : t -> Flx_types.bid_t -> string

(** Searches the bound symbol table for the given symbol. *)
val find_with_parent :
  t ->
  Flx_types.bid_t ->
  Flx_types.bid_t option * Flx_sym.t

(** Searches the symbol table for the given symbol's parent. *)
val find_parent : t -> Flx_types.bid_t -> Flx_types.bid_t option

(** Remove an entry from the symbol table. *)
val remove : t -> Flx_types.bid_t -> unit

(** Iterate over all the items in the symbol table. *)
val iter :
  (Flx_types.bid_t -> Flx_types.bid_t option -> Flx_sym.t -> unit) ->
  t ->
  unit

(** Fold over all the items in the symbol table. *)
val fold :
  (Flx_types.bid_t -> Flx_types.bid_t option -> Flx_sym.t -> 'a -> 'a) ->
  t ->
  'a ->
  'a
