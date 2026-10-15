#!/usr/bin/env python3
"""
Re-trains the tiny embedded classifier used by the Android app.

Architecture:
  hashed unigram/bigram features (192) -> ReLU(24) -> softmax(7)

The runtime Android app does NOT require Python, NumPy, TensorFlow, internet,
or a cloud API. This script is developer tooling only.
"""
import json
import re
from pathlib import Path
import numpy as np

LABELS = ["ignore", "pending", "expense", "income", "refund", "transfer", "investment"]
INPUT_SIZE = 192
HIDDEN_SIZE = 24

def java_hash(s: str) -> int:
    h = 0
    for ch in s:
        h = (31 * h + ord(ch)) & 0xffffffff
    return h - 2**32 if h >= 2**31 else h

def vectorize(message: str) -> np.ndarray:
    text = message.lower()
    tokens = re.findall(r"[a-z0-9₹]+", text)
    feats = list(tokens)
    feats += [tokens[i] + "_" + tokens[i + 1] for i in range(len(tokens) - 1)]
    semantic = {
        "__future_pending__": ["will be debited", "scheduled", "upcoming", "due on", "not yet completed"],
        "__otp__": ["otp", "one time password"],
        "__promo__": ["offer", "special deal", "discount", "coupon", "use code", "book now", "shop now", "buy now", "apply now", "cashback offer", "reward points", "up to rs", "up to inr", "invest now", "start sip", "loan"],
        "__cta__": ["use code", "promo code", "book now", "shop now", "buy now", "apply now", "redeem now", "avail now", "invest now"],
        "__movement__": ["debited", "credited", "paid to", "paid successfully", "spent", "charged", "sent", "received from", "withdrawn", "deposited", "transferred", "refund credited", "units allotted", "order executed"],
        "__refund__": ["refund", "refunded", "reversal", "reversed", "returned"],
        "__credit__": ["credited", "received", "salary", "cashback"],
        "__debit__": ["debited", "paid", "spent", "charged", "sent", "payment successful"],
        "__transfer__": ["self transfer", "own account", "between your accounts", "internal transfer", "moved between"],
        "__investment__": ["sip", "mutual fund", "zerodha", "groww", "stocks", "stock purchase", "gold investment", "invested"],
    }
    for token, phrases in semantic.items():
        if any(p in text for p in phrases):
            feats.append(token)
    if "upi" in text:
        feats.append("__upi__")
    if "₹" in message or "rs" in text or "inr" in text:
        feats.append("__amount_marker__")
    if re.search(r"(?:rs\.?|inr|₹)\s*[0-9,]+(?:\.[0-9]{1,2})?\s*(?:off|discount|cashback)", text):
        feats.append("__discount_amount__")
    if re.search(r"(?:up to|save|get)\s*(?:rs\.?|inr|₹)\s*[0-9,]+", text):
        feats.append("__discount_amount__")
    if re.search(r"(?:up to\s*)?[0-9]{1,3}%\s*(?:off|discount|cashback)", text):
        feats.append("__discount_percent__")

    v = np.zeros(INPUT_SIZE, dtype=np.float32)
    for f in feats:
        v[abs(java_hash(f)) % INPUT_SIZE] += 1.0
    n = np.linalg.norm(v)
    return v / n if n else v

def softmax(z):
    z = z - z.max(axis=1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=1, keepdims=True)

def main():
    here = Path(__file__).resolve().parents[1]
    rows = json.loads((here / "ml" / "training_samples.json").read_text())
    X = np.stack([vectorize(r["text"]) for r in rows])
    y = np.array([LABELS.index(r["label"]) for r in rows])

    rng = np.random.default_rng(123)
    w1 = (rng.standard_normal((INPUT_SIZE, HIDDEN_SIZE)) * .08).astype(np.float32)
    b1 = np.zeros(HIDDEN_SIZE, np.float32)
    w2 = (rng.standard_normal((HIDDEN_SIZE, len(LABELS))) * .08).astype(np.float32)
    b2 = np.zeros(len(LABELS), np.float32)

    m = [np.zeros_like(a) for a in (w1, b1, w2, b2)]
    v = [np.zeros_like(a) for a in (w1, b1, w2, b2)]
    beta1, beta2, lr, eps = .9, .999, .02, 1e-8

    for step in range(1, 1201):
        z1 = X @ w1 + b1
        h = np.maximum(z1, 0)
        p = softmax(h @ w2 + b2)
        onehot = np.eye(len(LABELS), dtype=np.float32)[y]
        dz2 = (p - onehot) / len(X)
        dw2, db2 = h.T @ dz2 + 1e-4 * w2, dz2.sum(0)
        dz1 = (dz2 @ w2.T) * (z1 > 0)
        dw1, db1 = X.T @ dz1 + 1e-4 * w1, dz1.sum(0)
        for i, (param, grad) in enumerate(zip((w1,b1,w2,b2),(dw1,db1,dw2,db2))):
            m[i] = beta1*m[i] + (1-beta1)*grad
            v[i] = beta2*v[i] + (1-beta2)*(grad*grad)
            mh = m[i] / (1-beta1**step)
            vh = v[i] / (1-beta2**step)
            param -= lr * mh / (np.sqrt(vh) + eps)

    pred = softmax(np.maximum(X @ w1 + b1, 0) @ w2 + b2).argmax(1)
    print(f"training accuracy: {(pred == y).mean():.3f}")
    print("The Android runtime weights are embedded in TinyNeuralClassifier.kt.")
    print("If you retrain, export these arrays into that file before shipping.")

if __name__ == "__main__":
    main()
