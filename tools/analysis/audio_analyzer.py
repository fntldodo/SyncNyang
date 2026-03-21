import librosa
import json
import os
import hashlib
import sys

def analyze_audio(file_path, output_dir):
    print(f"Analyzing: {file_path}")
    
    # 1. Load audio
    y, sr = librosa.load(file_path)
    
    # 2. Extract BPM and Beats
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr).tolist()
    
    # 3. Detect Onsets (Percussive Peaks)
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    onset_frames = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr)
    onset_times = librosa.frames_to_time(onset_frames, sr=sr).tolist()
    
    # 4. Generate Hash
    hasher = hashlib.md5()
    with open(file_path, 'rb') as f:
        buf = f.read()
        hasher.update(buf)
    file_hash = hasher.hexdigest()
    
    # 5. Build Result
    result = {
        "source_file": os.path.basename(file_path),
        "source_hash": file_hash,
        "analysis_version": "1.1.0",
        "bpm": float(tempo),
        "beats": beat_times,
        "onsets": onset_times
    }
    
    # 6. Save
    song_id = os.path.splitext(os.path.basename(file_path))[0]
    output_path = os.path.join(output_dir, f"{song_id}_analysis.json")
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)
    
    print(f"Saved analysis to: {output_path}")
    return result

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python audio_analyzer.py <input_wav_or_mp3> <output_dir>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_dir = sys.argv[2]
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        
    analyze_audio(input_file, output_dir)
