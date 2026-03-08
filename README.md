
# WAN2.2 I2V LightX2V 4 Steps RunPod Serverless Worker

RunPod serverless worker for generating a video from a single image using a ComfyUI workflow.

## Overview

This worker:

- accepts an input image as a URL, local path, or Base64 string
- loads `workflow/i2v.json`
- applies prompt and generation settings
- runs the workflow through ComfyUI
- returns the generated video as a Base64 string

## Requirements

- Python 3.10+
- ComfyUI running on port `8188`
- `wget` available in the runtime
- Python dependencies:
  - `runpod`
  - `websocket-client`

## Environment

| Variable | Default | Description |
|---|---|---|
| `SERVER_ADDRESS` | `127.0.0.1` | ComfyUI server host |

## Input

Jobs must be sent in this format:

```json
{
  "input": {}
}
```

### Supported fields

| Field | Type | Default | Description |
|---|---|---|---|
| `image` | string | — | Auto-detects URL, path, or Base64 |
| `image_path` | string | — | Local image path |
| `image_url` | string | — | Remote image URL |
| `image_base64` | string | — | Base64-encoded image |
| `prompt` | string | `""` | Positive prompt |
| `negative_prompt` | string | `"slow motion"` | Negative prompt |
| `cfg` | float | `1.0` | CFG scale |
| `steps` | int | `4` | Sampling steps |
| `seed` | int | random | Random seed |
| `length` | int | `81` | Video length |
| `width` | number | `544` | Output width |
| `height` | number | `960` | Output height |
| `vfi_multiplier` | int | `2` | Frame interpolation multiplier |
| `motion_amp` | float | `1.15` | Motion amplitude |
| `fps` | int | `27` | Output frame rate |

### Image input priority

The worker resolves image input in this order:

1. `image`
2. `image_path`
3. `image_url`
4. `image_base64`
5. `/example_image.png`

## Notes

- `width` and `height` are rounded to the nearest multiple of `16`
- if `seed` is not provided, a random seed is used
- output video is returned as Base64

## Example Request

```json
{
  "input": {
    "image_url": "https://example.com/image.jpg",
    "prompt": "a cinematic shot of a woman walking in the wind",
    "negative_prompt": "slow motion",
    "cfg": 1.0,
    "steps": 4,
    "seed": 123456,
    "length": 81,
    "width": 544,
    "height": 960,
    "vfi_multiplier": 2,
    "motion_amp": 1.15,
    "fps": 27
  }
}
```

## Response

### Success

```json
{
  "video": "<base64-encoded-video>"
}
```

### Error

```json
{
  "error": "Could not find the video."
}
```

## Workflow Assumptions

This worker expects the following node IDs in `workflow/i2v.json`:

| Node ID | Purpose |
|---|---|
| `57` | First sampler |
| `58` | Second sampler |
| `78` | Image input |
| `6` | Positive prompt |
| `7` | Negative prompt |
| `81` | FPS |
| `82` | VFI multiplier |
| `83` | Width / height / length / motion amplitude |

If the workflow changes, update the handler accordingly.

## Running

```bash
python handler.py
```

Ensure:

- ComfyUI is reachable at `http://<SERVER_ADDRESS>:8188`
- `workflow/i2v.json` exists
- dependencies are installed


[![Runpod](https://api.runpod.io/badge/josephlow5/wan22_i2v_serverless)](https://console.runpod.io/hub/josephlow5/wan22_i2v_serverless)