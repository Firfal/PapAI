/* Synthèse de la WebView : seules les voix françaises locales sont autorisées. */
(function (root) {
  'use strict';
  class Narration {
    constructor(synth, Utterance, storage) {
      this.synth = synth;
      this.Utterance = Utterance;
      this.storage = storage;
      this.enabled = true;
      try { this.enabled = storage.getItem('papai.readAloud') !== 'false'; } catch (_) {}
      this.assistance = false;
      this.allowed = false;
      this.dictating = false;
      this.seen = new Set();
      this.pending = [];
      this.current = null;
      if (synth && synth.addEventListener) synth.addEventListener('voiceschanged', () => this.pump());
    }
    setEnabled(on) {
      this.enabled = !!on;
      try { this.storage.setItem('papai.readAloud', String(this.enabled)); } catch (_) {}
      this.reconcile();
    }
    setDictating(on) {
      this.dictating = !!on;
      this.reconcile();
    }
    update(snap) {
      const assistance = snap.screen === 'session' && !!snap.sessionOpen;
      if (assistance && !this.assistance) this.seen.clear();
      this.assistance = assistance;
      this.allowed = assistance && snap.connected && snap.state === 'active' && !snap.paused && !snap.alert;
      this.dictating = !!(snap.dictation && snap.dictation.phase !== 'idle');
      this.reconcile();
      if (assistance && snap.currentAction) this.enqueue(snap.currentAction);
    }
    canRead() { return this.enabled && !this.dictating && this.allowed && this.assistance; }
    enqueue(phrase) {
      const text = String(phrase).trim().replace(/\s+/g, ' ');
      if (!this.assistance || !text || this.seen.has(text)) return;
      this.seen.add(text);
      if (!this.canRead()) return;
      this.pending.push(text);
      this.pump();
    }
    reconcile() {
      if (!this.canRead()) this.cancel();
      else this.pump();
    }
    cancel() {
      this.pending = [];
      const speaking = this.current !== null;
      this.current = null;
      if (speaking && this.synth) this.synth.cancel();
    }
    pump() {
      if (!this.canRead() || this.current || !this.pending.length || !this.synth || !this.Utterance) return;
      const voice = this.synth.getVoices().find(v => v.localService === true && /^fr(?:[-_]|$)/i.test(v.lang));
      // Aucun repli vers une voix distante, même si elle est la voix par défaut.
      if (!voice) return;
      const utterance = new this.Utterance(this.pending.shift());
      utterance.voice = voice;
      utterance.lang = voice.lang;
      const finish = () => {
        if (this.current !== utterance) return;
        this.current = null;
        this.pump();
      };
      utterance.onend = finish;
      utterance.onerror = finish;
      this.current = utterance;
      try { this.synth.speak(utterance); } catch (_) { finish(); }
    }
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = Narration;
  else {
    let storage;
    try { storage = root.localStorage; } catch (_) {}
    root.PapAINarration = new Narration(root.speechSynthesis, root.SpeechSynthesisUtterance, storage);
    root.addEventListener('beforeunload', () => root.PapAINarration.cancel());
  }
})(typeof window !== 'undefined' ? window : globalThis);
