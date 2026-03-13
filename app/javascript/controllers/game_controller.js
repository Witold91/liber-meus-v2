import { Controller } from "@hotwired/stimulus"

const DIFFICULTY_THRESHOLD = { easy: 1, medium: 4, hard: 7 }

export default class extends Controller {
  static targets = ["input", "submit", "worldPanel", "worldBtn"]
  static values = { gameId: Number }

  connect() {
    this.turnLog = document.getElementById("turn-log")
    this.scrollFrame = null
    this.streamingEl = null

    if (!this.turnLog) return

    this.turnLogObserver = new MutationObserver(() => {
      this.scheduleScrollToBottom()
    })

    this.turnLogObserver.observe(this.turnLog, {
      childList: true,
      subtree: true,
      characterData: true
    })

    this.scheduleScrollToBottom()
    this.subscribeToChannel()
  }

  disconnect() {
    if (this.turnLogObserver) this.turnLogObserver.disconnect()
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)
    if (this.subscription) this.subscription.unsubscribe()
  }

  subscribeToChannel() {
    if (!this.hasGameIdValue) return

    this.subscription = window.cable.subscriptions.create(
      { channel: "GameChannel", game_id: this.gameIdValue },
      {
        connected: () => console.log("[GameChannel] connected, game:", this.gameIdValue),
        rejected: () => console.warn("[GameChannel] subscription rejected"),
        received: (data) => this.handleCableMessage(data)
      }
    )
  }

  handleCableMessage(data) {
    if (data.type === "roll_result") {
      this.renderStreamingRoll(data)
    } else if (data.type === "chunk") {
      this.appendNarrativeChunk(data.text)
    }
  }

  renderStreamingRoll(data) {
    if (!this.streamingEl) return

    const { roll, difficulty, momentum, resolution_tag, health_loss, health_gain } = data
    const rollArea = this.streamingEl.querySelector(".roll-breakdown")
    if (!rollArea) return

    const isTrivial = difficulty === "trivial"
    const isImpossible = difficulty === "impossible"

    if (isTrivial || isImpossible) {
      rollArea.innerHTML =
        `<span class="turn-meta">[${resolution_tag}]</span>`
      return
    }

    if (!roll) return

    const threshold = DIFFICULTY_THRESHOLD[difficulty] || 4
    const total = roll + (momentum || 0)
    const momentumSign = (momentum || 0) >= 0 ? `+${momentum || 0}` : `${momentum}`

    rollArea.innerHTML =
      `<span class="roll-die">${roll}</span>` +
      `<span class="roll-op">d6</span>` +
      `<span class="roll-op">+</span>` +
      `<span class="roll-total">${momentumSign}</span>` +
      `<span class="roll-op">momentum</span>` +
      `<span class="roll-op">=</span>` +
      `<span class="roll-total">${total}</span>` +
      `<span class="roll-vs">vs</span>` +
      `<span class="roll-threshold">${threshold}</span>` +
      `<span class="roll-difficulty">(${difficulty})</span>` +
      `<span class="roll-verdict ${resolution_tag}">${resolution_tag.toUpperCase()}</span>`

    if (health_loss > 0) {
      const healthEl = document.createElement("div")
      healthEl.className = "health-loss"
      healthEl.innerHTML =
        `<span class="health-loss-icon">\u2665</span>` +
        `<span class="health-loss-value">\u2212${health_loss}</span>` +
        `<span>health</span>`
      rollArea.insertAdjacentElement("afterend", healthEl)
    }

    if (health_gain > 0) {
      const healEl = document.createElement("div")
      healEl.className = "health-gain"
      healEl.innerHTML =
        `<span class="health-gain-icon">\u2665</span>` +
        `<span class="health-gain-value">+${health_gain}</span>` +
        `<span>health</span>`
      const insertAfter = rollArea.parentElement.querySelector(".health-loss") || rollArea
      insertAfter.insertAdjacentElement("afterend", healEl)
    }
  }

  appendNarrativeChunk(text) {
    if (!this.streamingEl) return
    const narrativeEl = this.streamingEl.querySelector(".turn-narrative")
    if (!narrativeEl) return

    // Buffer contains raw JSON string content (escapes like \n, \\, \").
    // Use JSON.parse to properly unescape all sequences.
    this.narrativeBuffer = (this.narrativeBuffer || "") + text
    let buf = this.narrativeBuffer
    // Strip trailing incomplete escape so JSON.parse doesn't choke mid-stream
    if (buf.endsWith("\\")) buf = buf.slice(0, -1)
    try {
      narrativeEl.textContent = JSON.parse('"' + buf + '"')
    } catch {
      narrativeEl.textContent = buf.replace(/\\n/g, "\n").replace(/\\t/g, "\t").replace(/\\\\/g, "\\")
    }
  }

  handleSubmit(event) {
    event.preventDefault()

    const action = this.inputTarget.value.trim()
    if (!action) return

    const log = this.turnLog || document.getElementById("turn-log")
    if (log) {
      // Append user action
      const userMsg = document.createElement("div")
      userMsg.style.cssText = "font-style:italic;color:#666;border-left:2px solid #444;padding-left:0.75rem;"
      userMsg.textContent = `> ${action}`
      log.appendChild(userMsg)

      // Create streaming placeholder
      this.narrativeBuffer = ""
      this.streamingEl = document.createElement("div")
      this.streamingEl.id = "streaming-turn"
      this.streamingEl.className = "turn-entry streaming"
      this.streamingEl.innerHTML =
        `<div class="roll-breakdown"></div>` +
        `<div class="turn-narrative"></div>`
      log.appendChild(this.streamingEl)
      this.scheduleScrollToBottom()
    }

    const form = event.target
    const formData = new FormData(form)

    this.inputTarget.disabled = true
    this.submitTarget.disabled = true
    this.submitTarget.textContent = "\u2026"

    fetch(form.action, {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        "Accept": "text/vnd.turbo-stream.html, text/html"
      },
      body: formData
    })
      .then(response => response.text())
      .then(html => {
        // Remove streaming placeholder before rendering final turn
        if (this.streamingEl) {
          this.streamingEl.remove()
          this.streamingEl = null
        }
        Turbo.renderStreamMessage(html)
        this.scheduleScrollToBottom()

        // Check if an ending turn was rendered — server will remove the form via Turbo
        if (this.turnLog && this.turnLog.querySelector(".turn-entry.ending")) {
          this.gameEnded = true
        }
      })
      .catch(err => {
        console.error("Game submit error:", err)
        if (this.streamingEl) {
          this.streamingEl.remove()
          this.streamingEl = null
        }
      })
      .finally(() => {
        if (this.gameEnded) return
        if (!this.hasInputTarget) return
        this.inputTarget.value = ""
        this.inputTarget.disabled = false
        this.submitTarget.disabled = false
        this.submitTarget.textContent = "\u2192"
        this.inputTarget.focus()
      })
  }

  fillAction(event) {
    const label = event.currentTarget.dataset.label
    if (!label || !this.hasInputTarget) return
    this.inputTarget.value = label
    this.inputTarget.focus()
  }

  toggleWorldInfo() {
    const open = this.worldPanelTarget.classList.toggle("mobile-open")
    if (this.hasWorldBtnTarget) {
      this.worldBtnTarget.textContent = open ? "\u2715" : "World"
    }
  }

  scheduleScrollToBottom() {
    if (!this.turnLog) return
    if (this.scrollFrame) cancelAnimationFrame(this.scrollFrame)

    this.scrollFrame = requestAnimationFrame(() => {
      this.turnLog.scrollTop = this.turnLog.scrollHeight
      this.scrollFrame = null
    })
  }
}
