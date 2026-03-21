import json
import os
import random
import sys

# Format Version for the generator logic itself to allow for stable migrations/re-runs
GENERATOR_VERSION = "1.2.0"

def generate_draft(analysis_path, output_dir, difficulty="Normal"):
    if not os.path.exists(analysis_path):
        print(f"Error: Analysis file not found: {analysis_path}")
        return False

    with open(analysis_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    song_id = data.get("song_id", data["source_file"].split('.')[0])
    source_hash = data.get("source_hash", "0")
    beats = data.get("beats", [])
    
    # --- DETERMINISTIC SEEDING ---
    # Stable per song_id, source_hash (content), difficulty, and generator version.
    seed_string = f"{song_id}_{source_hash}_{difficulty}_{GENERATOR_VERSION}"
    random.seed(seed_string)
    
    notes = []
    last_lane = -1
    consecutive_lane_count = 0
    
    # Heuristic: 1 note per beat (Normal), 1 note per 2 beats (Easy)
    step = 1 if difficulty == "Normal" else 2
    
    for i in range(0, len(beats), step):
        t = beats[i]
        
        possible_lanes = [0, 1, 2]
        # Avoid 3+ consecutive notes in the same lane
        if consecutive_lane_count >= 2:
            if last_lane in possible_lanes:
                possible_lanes.remove(last_lane)
        
        lane = random.choice(possible_lanes)
        
        if lane == last_lane:
            consecutive_lane_count += 1
        else:
            consecutive_lane_count = 1
            last_lane = lane
            
        notes.append({"t": round(t, 3), "l": lane})
    
    # Build Chart JSON with full metadata schema
    chart = {
        "format_version": "1.1.0",
        "generator_info": {
            "version": GENERATOR_VERSION,
            "seed": seed_string
        },
        "song_id": song_id,
        "metadata": {
            "title": song_id.replace('_', ' ').title(),
            "artist": data.get("artist", "Unknown"),
            "bpm": round(data.get("bpm", 120.0), 1),
            "difficulty": difficulty,
            "duration": data.get("duration", 0.0)
        },
        "config": {
            "audio_path": f"res://assets/assets_audio_/{data['source_file']}",
            "song_offset": 0.0
        },
        "notes": notes,
        "source_hash": source_hash
    }
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    output_path = os.path.join(output_dir, f"{song_id}.json")
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(chart, f, indent=2, ensure_ascii=False)
    
    print(f"Generated deterministic draft: {output_path}")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python draft_generator.py <analysis_json> <output_dir> [difficulty]")
        sys.exit(1)
        
    generate_draft(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "Normal")
