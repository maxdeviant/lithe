import Lithe.Dom
import Lithe.Subscription

/-!
The built-in sources of outside events, which only exist in the browser.
-/

namespace Lithe

namespace Raw

@[extern js inline "window"]
opaque window : BaseIO JsValue

@[extern js inline "document"]
opaque document : BaseIO JsValue

@[extern js inline "performance.now()"]
opaque now : BaseIO Float

@[extern js inline "setInterval(#1, Number(#2))"]
opaque setInterval (f : @& JsValue) (ms : @& Nat) : BaseIO JsValue

@[extern js inline "(clearInterval(#1), 0)"]
opaque clearInterval (id : @& JsValue) : BaseIO Unit

@[extern js inline "requestAnimationFrame(#1)"]
opaque requestAnimationFrame (f : @& JsValue) : BaseIO JsValue

@[extern js inline "(cancelAnimationFrame(#1), 0)"]
opaque cancelAnimationFrame (id : @& JsValue) : BaseIO Unit

end Raw

namespace Subscription

/-- Starts listening for events of the type `type` on `target`, and returns what stops it. -/
private def listen (target : JsValue) (type : String) (send : Event → IO Bool) : IO (IO Unit) := do
  let onEvent : JsValue → IO Unit := fun e => do
    if ← send (← Event.ofJs e) then
      Raw.preventDefault e
  let listener ← toJs onEvent
  Raw.addEventListener target type listener false
  return Raw.removeEventListener target type listener

/-- Listens for events of the type `type` on `window`. -/
def onWindow [ToHandler α Msg] (type : String) (a : α) : Subscription Msg :=
  source s!"window:{type}" a fun send => do listen (← Raw.window) type send

/-- Listens for events of the type `type` on `document`. -/
def onDocument [ToHandler α Msg] (type : String) (a : α) : Subscription Msg :=
  source s!"document:{type}" a fun send => do listen (← Raw.document) type send

/-- Sends a message every `ms` milliseconds, as an event whose `timeStamp` is the current time. -/
def every [ToHandler α Msg] (ms : Nat) (a : α) : Subscription Msg :=
  source s!"every:{ms}" a fun send => do
    let onTick : IO Unit := do
      discard <| send { type := "tick", timeStamp := ← Raw.now }
    let id ← Raw.setInterval (← toJs onTick) ms
    return Raw.clearInterval id

/-- Sends a message before each repaint, as an event whose `timeStamp` is the frame's time. -/
def animationFrame [ToHandler α Msg] (a : α) : Subscription Msg :=
  source "animationFrame" a fun send => do
    let id ← IO.mkRef JsValue.undefined
    let callback ← IO.mkRef JsValue.undefined
    let onFrame : Float → IO Unit := fun timeStamp => do
      discard <| send { type := "animationframe", timeStamp }
      id.set (← Raw.requestAnimationFrame (← callback.get))
    callback.set (← toJs onFrame)
    id.set (← Raw.requestAnimationFrame (← callback.get))
    return do Raw.cancelAnimationFrame (← id.get)

end Subscription

end Lithe
