module

import Counter
import Std.Http

open Lithe Std Std.Async Std.Http

/-! The server, which is a native program. It serves the client's build, with the page already in it. -/

/-- Returns the type of a file with the extension `ext`. -/
def contentType : Option String → String
  | some "js" => "text/javascript"
  | some "css" => "text/css"
  | some "html" => "text/html; charset=utf-8"
  | _ => "application/octet-stream"

/-- Returns `template` with the page for `model` in its element for the app, and `model` after it. -/
def renderPage (template : String) (model : Model) : String :=
  template.replace "<div id=\"app\"></div>"
    s!"<div id=\"app\">{(view model).render}</div>{jsonScript "model" model}"

/-- Returns the count that the query of a request asks for, as in `?count=5`. -/
def countOf (query : String) : Nat :=
  ((query.splitOn "count=")[1]?.bind String.toNat?).getD initial.count

/-- What the server needs to respond to requests. -/
structure Site where
  /-- The directory of the client's build. -/
  dist : System.FilePath
  /-- The HTML of the client's build, which has no content yet. -/
  template : String

/-- Returns the response for a request for `target`. -/
def Site.respond (site : Site) (target : String) : Async (Response Body.Full) := do
  let path := (target.splitOn "?").head!
  if path == "/" then
    let query := ((target.splitOn "?")[1]?).getD ""
    return ← Response.ok |>.html (renderPage site.template (initial (countOf query)))
  -- Encoded characters are never in the client's build, so this also rules out an encoded `..`.
  if path.contains '%' || (path.splitOn "/").contains ".." then
    return ← Response.notFound |>.text "Not found"
  let file := site.dist / (path.drop 1).toString
  if !(← file.pathExists) || (← file.isDir) then
    return ← Response.notFound |>.text "Not found"
  Response.ok
    |>.header! "Content-Type" (contentType file.extension)
    |>.fromBytes (← IO.FS.readBinFile file)

instance : Server.Handler Site where
  ResponseBody := Body.Full
  onRequest site request := site.respond (toString request.line.uri)

/-- Serves `dist` on `port`, where 0 means any port, until the program is stopped. -/
def serve (port : UInt16) (dist : System.FilePath) : Async Unit := do
  let template ← IO.FS.readFile (dist / "index.html")
  let address : Net.SocketAddress := .v4 { addr := .ofParts 127 0 0 1, port }
  let server ← Server.serve address ({ dist, template } : Site)
  let some (.v4 bound) := server.localAddr | throw (.userError "the server has no address")
  IO.println s!"listening on http://localhost:{bound.port}/"
  (← IO.getStdout).flush
  server.waitShutdown

public def main (args : List String) : IO Unit := do
  let port := (args[0]?.bind String.toNat?).getD 3000
  let dist := args[1]?.getD "dist"
  (serve port.toUInt16 dist).block
