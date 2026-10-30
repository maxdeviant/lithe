/-! What the URL says to show, which goes in its hash so that links and the back button just work. -/

/-- A place in the app. -/
inductive Route where
  /-- Only the board. -/
  | board
  /-- The board, with the card `id` open. -/
  | card (id : Nat)
  deriving BEq

/-- Returns the route for the hash of a URL, including its `#`. Anything unknown is the board. -/
def Route.parse (hash : String) : Route :=
  match hash.splitOn "/" with
  | ["#", "card", id] => (id.toNat?.map .card).getD .board
  | _ => .board

/-- Returns the hash of the URL for `r`. -/
def Route.href : Route → String
  | .board => "#/"
  | .card id => s!"#/card/{id}"

#guard Route.parse (Route.href .board) == .board
#guard Route.parse (Route.href (.card 12)) == .card 12
#guard Route.parse "" == .board
#guard Route.parse "#/card/nope" == .board
