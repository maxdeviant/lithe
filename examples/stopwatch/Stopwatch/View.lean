import Lithe
import Stopwatch.Model

open Lithe

/-- Pads `n` with zeros to `width` digits. -/
def pad (width n : Nat) : String :=
  let s := toString n
  "".pushn '0' (width - s.length) ++ s

/-- Returns `ms` in the form `mm:ss.t`. -/
def formatTime (ms : Float) : String :=
  let tenths := (ms / 100).toUInt64.toNat
  s!"{pad 2 (tenths / 600)}:{pad 2 (tenths / 10 % 60)}.{tenths % 10}"

/-- Returns the message for starting or stopping at the time of the event `e`. -/
def toggleAt (e : Lithe.Event) : Msg :=
  .toggle e.timeStamp

/-- Returns the page for `m`. -/
def view (m : Model) : Html Msg :=
  <main>
    <h1 id="time">{formatTime m.elapsed}</h1>
    <button id="toggle" onclick={toggleAt}>{if m.running then "Stop" else "Start"}</button>
    <button id="lap" onclick={Msg.lap}>Lap</button>
    <button id="reset" onclick={Msg.reset}>Reset</button>
    <p><kbd>s</kbd> start or stop, <kbd>l</kbd> lap, <kbd>r</kbd> reset</p>
    <ol id="laps">
      {Html.forEach m.laps.zipIdx (fun (_, i) => m.laps.size - i)
        fun (lap, _) => <li>{formatTime lap}</li>}
    </ol>
  </main>
