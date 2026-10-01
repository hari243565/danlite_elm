#!/usr/bin/env python3
"""Reproduces the review sample of the batch 1 independent review (RUN_MODE=review, seed 20261001).

A. every STOP entry in generic_en_seed.jsonl
B. 30 random non-STOP entries from batch 1 (rank > 40) and 10 random non-STOP pilot entries (rank <= 40)
Both lists are sorted by code before sampling, then random.sample with random.seed(20261001).

Usage: python3 review_sample_batch1_20261001.py   (prints the three lists)
"""
import csv
import json
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(line) for line in open(os.path.join(HERE, "generic_en_seed.jsonl"), encoding="utf-8") if line.strip()]
rank = {r["code"]: int(r["rank"]) for r in csv.DictReader(open(os.path.join(HERE, "relevance_ranking.csv"), encoding="utf-8"))}
stop = [r["code"] for r in rows if r["rider_action_level"] == "STOP"]
pilot = [r["code"] for r in rows if rank[r["code"]] <= 40]
batch1 = [r["code"] for r in rows if rank[r["code"]] > 40]
random.seed(20261001)
s_batch1 = sorted(random.sample(sorted(c for c in batch1 if c not in stop), 30))
s_pilot = sorted(random.sample(sorted(c for c in pilot if c not in stop), 10))
if __name__ == "__main__":
    print("STOP (all):", len(stop), stop)
    print("batch 1 random non-STOP:", len(s_batch1), s_batch1)
    print("pilot random non-STOP:", len(s_pilot), s_pilot)
