/-! The state of the stopwatch, and the updates to it. Times are in milliseconds. -/

/-- The state of the stopwatch. -/
structure Model where
  /-- Whether the stopwatch is running. -/
  running : Bool := false
  /-- The time counted so far. -/
  elapsed : Float := 0
  /-- When `elapsed` was last brought up to date. -/
  lastTick : Float := 0
  /-- The value of `elapsed` at each lap, latest first. -/
  laps : Array Float := #[]

/-- The things that can happen. -/
inductive Msg where
  /-- Starts or stops the stopwatch at the time `now`. -/
  | toggle (now : Float)
  /-- The time is now `now`. -/
  | tick (now : Float)
  /-- Records a lap. -/
  | lap
  /-- Goes back to the beginning. -/
  | reset

/-- Returns `m` with `elapsed` brought up to the time `now`. -/
def Model.advance (m : Model) (now : Float) : Model :=
  if m.running then
    { m with elapsed := m.elapsed + (now - m.lastTick), lastTick := now }
  else
    m

/-- Returns the state after `msg`. -/
def Model.update (m : Model) : Msg → Model
  | .toggle now =>
    let m := m.advance now
    { m with running := !m.running, lastTick := now }
  | .tick now => m.advance now
  | .lap => if m.running then { m with laps := #[m.elapsed] ++ m.laps } else m
  | .reset => { running := m.running, lastTick := m.lastTick }
