import os
import json
import hashlib
import subprocess
import sys

# --- FOLDER LIFECYCLE CONFIG (External Paths) ---
BASE_DIR = os.getcwd()
RAW_AUDIO_DIR = os.path.join(BASE_DIR, "tools/analysis/raw")
ANALYSIS_DIR = os.path.join(BASE_DIR, "tools/analysis/output/analysis")
DRAFTS_DIR = os.path.join(BASE_DIR, "tools/analysis/output/drafts")

# --- GODOT RUNTIME PATHS (Project Paths) ---
GODOT_DATA_DIR = os.path.join(BASE_DIR, "data/charts")
MANIFEST_PATH = os.path.join(BASE_DIR, "data/manifest.json")

def get_file_hash(path):
    hasher = hashlib.md5()
    with open(path, 'rb') as f:
        while chunk := f.read(8192):
            hasher.update(chunk)
    return hasher.hexdigest()

def sync_pipeline():
    print("=== SyncNyang Stage 2B Production Pipeline ===")
    
    # 3. Ensure all required directories are created safely
    try:
        os.makedirs(RAW_AUDIO_DIR, exist_ok=True)
        os.makedirs(ANALYSIS_DIR, exist_ok=True)
        os.makedirs(DRAFTS_DIR, exist_ok=True)
        os.makedirs(GODOT_DATA_DIR, exist_ok=True)
    except Exception as e:
        print(f"Error creating directories: {e}")
        sys.exit(1)

    # 1. Load existing manifest for idempotency
    manifest_data = {}
    if os.path.exists(MANIFEST_PATH):
        try:
            with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
                list_data = json.load(f)
                manifest_data = {item["song_id"]: item for item in list_data}
        except Exception as e:
            print(f"Warning: manifest.json corrupt or empty ({e}). Starting fresh.")

    # 2. Process Raw Audio
    audio_files = [f for f in os.listdir(RAW_AUDIO_DIR) if f.endswith(('.mp3', '.wav'))]
    if not audio_files:
        print("No raw audio files found in tools/analysis/raw/")
        return

    new_manifest_entries = {}
    
    for audio_name in audio_files:
        song_id = os.path.splitext(audio_name)[0]
        raw_path = os.path.join(RAW_AUDIO_DIR, audio_name)
        current_hash = get_file_hash(raw_path)
        
        analysis_path = os.path.join(ANALYSIS_DIR, f"{song_id}_analysis.json")
        draft_path = os.path.join(DRAFTS_DIR, f"{song_id}.json")
        final_chart_path = os.path.join(GODOT_DATA_DIR, f"{song_id}.json")

        try:
            # --- CHANGED-SONG DETECTION (Hash Based) ---
            need_analysis = True
            if os.path.exists(analysis_path):
                with open(analysis_path, 'r', encoding='utf-8') as f:
                    cached = json.load(f)
                    if cached.get("source_hash") == current_hash:
                        need_analysis = False
            
            if need_analysis:
                print(f"[*] Analyzing: {audio_name} (New/Changed)")
                # 2. Subprocess failure handling (check=True)
                subprocess.run(["python", "tools/analysis/audio_analyzer.py", raw_path, ANALYSIS_DIR], check=True)
            
            # --- OVERWRITE PROTECTION (Folder Based) ---
            # Only generate draft if no final/manual chart exists in data/charts/
            is_finalized = os.path.exists(final_chart_path)
            if is_finalized:
                print(f"[-] Protected: Final chart exists for '{song_id}'. Skipping draft generation.")
                active_res_path = f"res://data/charts/{song_id}.json"
            else:
                print(f"[+] Generating Draft: {song_id}")
                subprocess.run(["python", "tools/analysis/draft_generator.py", analysis_path, DRAFTS_DIR], check=True)
                active_res_path = f"res://tools/analysis/output/drafts/{song_id}.json"

            # --- STRENGTHEN MANIFEST DEFAULTS ---
            if song_id in manifest_data:
                entry = manifest_data[song_id]
                entry["chart_path"] = active_res_path
                # Update source_hash if added to manifest for better tracking
                entry["source_hash"] = current_hash
            else:
                # 4. Strengthen new manifest entry defaults
                entry = {
                    "song_id": song_id,
                    "title": song_id.replace('_', ' ').title(),
                    "artist": "Unknown",
                    "duration": 0.0,
                    "preview_start": 0.0,
                    "chart_path": active_res_path,
                    "audio_path": f"res://assets/assets_audio_/{audio_name}",
                    "difficulty": "Normal",
                    "source_hash": current_hash
                }
            
            new_manifest_entries[song_id] = entry

        except subprocess.CalledProcessError as e:
            print(f"Error: Subprocess failed for {song_id}: {e}")
            # If a critical step fails, we do NOT add/update this song in the manifest result
            continue
        except Exception as e:
            print(f"Unexpected error processing {song_id}: {e}")
            continue

    # 3. Finalize Manifest (Idempotent update)
    # We reconstruct the manifest from our processed entries to ensure stale/failed songs aren't causing issues
    final_manifest = list(new_manifest_entries.values())
    
    # 2. Do not write broken manifest state: only save if we have entries or at least didn't crash
    with open(MANIFEST_PATH, 'w', encoding='utf-8') as f:
        json.dump(final_manifest, f, indent=2, ensure_ascii=False)
    
    print(f"=== Sync Done: {len(final_manifest)} songs registered in manifest. ===")

if __name__ == "__main__":
    sync_pipeline()
