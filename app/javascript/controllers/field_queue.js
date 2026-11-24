// Offline queue of field operations, shared by the field-sync controller (work
// order screen) and the field-status chip of the field top bar.
//
// Each operation (device-generated id, kind, the version the technician saw,
// payload) is kept in localStorage until the server answers. Operations are
// sent in order; the server stores the outcome per operation id, so a resend
// never applies twice. Keys use the "servora:" prefix plus the
// user/organization context key, so the local-context controller removes
// everything on logout or context switch.
//
// Every change of the queue or of the connection is announced as a window
// event "field-sync:status" with { state, pending }:
//   synced   nothing waiting to be sent;
//   pending  operations waiting while the device is online (being sent);
//   offline  the device reports no connection;
//   error    the last attempt failed although the device reports a connection.
// "field-sync:retry" asks whoever sends the queue on this screen to try again.
export const PREFIX = "servora:field:"
export const STATUS_EVENT = "field-sync:status"
export const RETRY_EVENT = "field-sync:retry"

// Shared by every controller of the page (ES modules are evaluated once), so
// two controllers never send the same queue at the same time.
let flushing = false
let failure = null

const queueKey = (contextKey) => `${PREFIX}${contextKey}:queue`
const parkedKey = (contextKey) => `${PREFIX}${contextKey}:outcomes`

function read(key) {
  try { return JSON.parse(localStorage.getItem(key)) || [] } catch { return [] }
}

export function readQueue(contextKey) {
  return read(queueKey(contextKey))
}

export function writeQueue(contextKey, queue) {
  localStorage.setItem(queueKey(contextKey), JSON.stringify(queue))
  announce(contextKey)
}

export function enqueue(contextKey, operation) {
  writeQueue(contextKey, [...readQueue(contextKey), operation])
}

export function currentStatus(contextKey) {
  const pending = readQueue(contextKey).length
  let state = "pending"
  if (!navigator.onLine) state = "offline"
  else if (pending === 0) state = "synced"
  else if (failure && !flushing) state = "error"
  return { state, pending }
}

export function announce(contextKey) {
  window.dispatchEvent(new CustomEvent(STATUS_EVENT, { detail: currentStatus(contextKey) }))
}

// Outcomes that could not be shown where they happened (a refused or
// conflicting operation sent from the agenda) wait here for the screen of
// their work order.
export function park(contextKey, operation, outcome) {
  const { payload, ...summary } = operation
  localStorage.setItem(parkedKey(contextKey), JSON.stringify([...read(parkedKey(contextKey)), { operation: summary, outcome }]))
}

export function takeParked(contextKey, workOrderId) {
  const all = read(parkedKey(contextKey))
  const mine = all.filter((entry) => entry.operation.work_order_id === workOrderId)
  if (mine.length > 0) {
    localStorage.setItem(parkedKey(contextKey), JSON.stringify(all.filter((entry) => !mine.includes(entry))))
  }
  return mine
}

// Sends the queued operations in order. onOutcome(operation, outcome) runs for
// every answer; onFailure(kind) when sending stops ("network" or "server").
// Returns false when another send is already running.
export async function flush({ url, contextKey, onOutcome = () => {}, onFailure = () => {} }) {
  if (flushing) return false
  flushing = true
  failure = null
  announce(contextKey)
  try {
    for (const operation of readQueue(contextKey)) {
      const outcome = await send(url, operation)
      if (outcome.failure) {
        failure = outcome.failure
        onFailure(outcome.failure)
        break
      }
      writeQueue(contextKey, chainVisitVersions(readQueue(contextKey).filter((queued) => queued.id !== operation.id),
        operation, outcome))
      if (operation.draft) localStorage.removeItem(operation.draft)
      onOutcome(operation, outcome)
    }
  } finally {
    flushing = false
    announce(contextKey)
  }
  return true
}

// Visit operations recorded one after another while offline (the trip, then
// "cliente ausente") were all based on the version seen on screen. Once one of
// them is applied, the later ones of the same visit that shared that version
// move to the new one, so the sequence the technician recorded is not reported
// as a change made by someone else.
export function chainVisitVersions(queue, applied, outcome) {
  const visitId = applied.payload?.visit_id
  const nextVersion = outcome?.result?.version
  if (outcome?.status !== "applied" || !applied.kind?.startsWith("visit_") || !visitId || nextVersion == null) return queue

  return queue.map((queued) => {
    const sameVisit = queued.kind?.startsWith("visit_") && queued.payload?.visit_id === visitId
    return sameVisit && String(queued.version) === String(applied.version) ? { ...queued, version: nextVersion } : queued
  })
}

async function send(url, operation) {
  const { draft, ...body } = operation
  let response
  try {
    response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      },
      body: JSON.stringify({ operation: body })
    })
  } catch {
    return { failure: "network" }
  }
  if (response.status === 429 || response.status >= 500) return { failure: "server" }
  if (response.status === 403 || response.status === 404) {
    return { status: "rejected", result: { error: "Você não tem mais acesso a esta ordem ou ela foi encerrada." } }
  }
  try {
    return await response.json()
  } catch {
    // Not a JSON answer (an expired session redirects to the sign-in page):
    // the operation stays queued.
    return { failure: "server" }
  }
}
