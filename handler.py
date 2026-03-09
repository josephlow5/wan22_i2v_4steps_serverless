import runpod
from runpod.serverless.utils import rp_upload
import os
import websocket
import base64
import json
import uuid
import logging
import urllib.request
import urllib.parse
import binascii  # Import for Base64 error handling
import subprocess
import time
import random

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

server_address = os.getenv('SERVER_ADDRESS', '127.0.0.1')
client_id = str(uuid.uuid4())


def to_nearest_multiple_of_16(value):
    """Adjust the given value to the nearest multiple of 16, minimum 16 guaranteed"""
    try:
        numeric_value = float(value)
    except Exception:
        raise Exception(f"width/height value is not numeric: {value}")
    adjusted = int(round(numeric_value / 16.0) * 16)
    if adjusted < 16:
        adjusted = 16
    return adjusted


def process_input(input_data, temp_dir, output_filename, input_type):
    """Process input data and return the file path"""
    if input_type == "path":
        # If it is a path, return as is
        logger.info(f"📁 Processing path input: {input_data}")
        return input_data
    elif input_type == "url":
        # If it is a URL, download it
        logger.info(f"🌐 Processing URL input: {input_data}")
        os.makedirs(temp_dir, exist_ok=True)
        file_path = os.path.abspath(os.path.join(temp_dir, output_filename))
        return download_file_from_url(input_data, file_path)
    elif input_type == "base64":
        # If it is Base64, decode and save
        logger.info(f"🔢 Processing Base64 input")
        return save_base64_to_file(input_data, temp_dir, output_filename)
    else:
        raise Exception(f"Unsupported input type: {input_type}")


def download_file_from_url(url, output_path):
    """Download a file from a URL"""
    try:
        # Download file using wget
        result = subprocess.run([
            'wget', '-O', output_path, '--no-verbose', url
        ], capture_output=True, text=True)
        if result.returncode == 0:
            logger.info(f"✅ Successfully downloaded file from URL: {url} -> {output_path}")
            return output_path
        else:
            logger.error(f"❌ wget download failed: {result.stderr}")
            raise Exception(f"URL download failed: {result.stderr}")
    except subprocess.TimeoutExpired:
        logger.error("❌ Download timed out")
        raise Exception("Download timed out")
    except Exception as e:
        logger.error(f"❌ Error occurred during download: {e}")
        raise Exception(f"Error occurred during download: {e}")


def save_base64_to_file(base64_data, temp_dir, output_filename):
    """Save Base64 data to a file"""
    try:
        # Decode Base64 string
        decoded_data = base64.b64decode(base64_data)
        # Create directory if it does not exist
        os.makedirs(temp_dir, exist_ok=True)
        # Save to file
        file_path = os.path.abspath(os.path.join(temp_dir, output_filename))
        with open(file_path, 'wb') as f:
            f.write(decoded_data)
        logger.info(f"✅ Saved Base64 input to file '{file_path}'.")
        return file_path
    except (binascii.Error, ValueError) as e:
        logger.error(f"❌ Base64 decoding failed: {e}")
        raise Exception(f"Base64 decoding failed: {e}")


def queue_prompt(prompt):
    url = f"http://{server_address}:8188/prompt"
    logger.info(f"Queueing prompt to: {url}")
    p = {"prompt": prompt, "client_id": client_id}
    data = json.dumps(p).encode('utf-8')
    req = urllib.request.Request(url, data=data)
    return json.loads(urllib.request.urlopen(req).read())


def get_image(filename, subfolder, folder_type):
    url = f"http://{server_address}:8188/view"
    logger.info(f"Getting image from: {url}")
    data = {"filename": filename, "subfolder": subfolder, "type": folder_type}
    url_values = urllib.parse.urlencode(data)
    with urllib.request.urlopen(f"{url}?{url_values}") as response:
        return response.read()


def get_history(prompt_id):
    url = f"http://{server_address}:8188/history/{prompt_id}"
    logger.info(f"Getting history from: {url}")
    with urllib.request.urlopen(url) as response:
        return json.loads(response.read())


def get_videos(ws, prompt):
    prompt_id = queue_prompt(prompt)['prompt_id']
    output_videos = {}
    while True:
        out = ws.recv()
        if isinstance(out, str):
            message = json.loads(out)
            if message['type'] == 'executing':
                data = message['data']
                if data['node'] is None and data['prompt_id'] == prompt_id:
                    break
        else:
            continue
    history = get_history(prompt_id)[prompt_id]
    for node_id in history['outputs']:
        node_output = history['outputs'][node_id]
        videos_output = []
        if 'gifs' in node_output:
            for video in node_output['gifs']:
                # Read the file directly using fullpath and encode to base64
                with open(video['fullpath'], 'rb') as f:
                    video_data = base64.b64encode(f.read()).decode('utf-8')
                videos_output.append(video_data)
        output_videos[node_id] = videos_output
    return output_videos


def load_workflow(workflow_path):
    """Load a workflow file"""
    # If relative path, convert to absolute path based on current file
    if not os.path.isabs(workflow_path):
        current_dir = os.path.dirname(os.path.abspath(__file__))
        workflow_path = os.path.join(current_dir, workflow_path)
    with open(workflow_path, 'r', encoding='utf-8') as file:
        return json.load(file)



def handler(job):
    job_input = job.get("input", {})
    logger.info(f"Received job input: {job_input}")
    task_id = f"task_{uuid.uuid4()}"

    # Image input processing (use only one of image, image_path, image_url, image_base64)
    image_path = None
    if "image" in job_input:
        # If image parameter is provided, automatically detect type
        image_data = job_input["image"]
        if isinstance(image_data, str):
            if image_data.startswith("http://") or image_data.startswith("https://"):
                image_path = process_input(image_data, task_id, "input_image.jpg", "url")
            elif os.path.exists(image_data) or image_data.startswith("/"):
                image_path = process_input(image_data, task_id, "input_image.jpg", "path")
            else:
                # Assume Base64
                image_path = process_input(image_data, task_id, "input_image.jpg", "base64")
        else:
            raise Exception("The image parameter must be a string.")
    elif "image_path" in job_input:
        image_path = process_input(job_input["image_path"], task_id, "input_image.jpg", "path")
    elif "image_url" in job_input:
        image_path = process_input(job_input["image_url"], task_id, "input_image.jpg", "url")
    elif "image_base64" in job_input:
        image_path = process_input(job_input["image_base64"], task_id, "input_image.jpg", "base64")
    else:
        # Use default value
        image_path = "/example_image.png"
        logger.info("Using default image file: /example_image.png")

    # Workflow file to use
    workflow_file = "workflow/i2v.json"
    logger.info(f"Using workflow: {workflow_file}")

    prompt = load_workflow(workflow_file)
    
    precision  = job_input.get("precision ", "fp8_s")
    if precision == "fp8_s":
        wan22_i2v_fp8_s_high_model = "wan2.2_i2v_A14b_high_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui_1030.safetensors"
        wan22_i2v_fp8_s_low_model = "wan2.2_i2v_A14b_low_noise_scaled_fp8_e4m3_lightx2v_4step_comfyui.safetensors"
        prompt["37"]["inputs"]["unet_name"] = wan22_i2v_fp8_s_high_model
        prompt["56"]["inputs"]["unet_name"] = wan22_i2v_fp8_s_low_model
        logger.info(f"using fp8_s model: {wan22_i2v_fp8_s_high_model}, {wan22_i2v_fp8_s_low_model}")
    elif precision == "fp16":
        wan22_i2v_fp16_high_model = "wan2.2_i2v_A14b_high_noise_lightx2v_4step_1030.safetensors"
        wan22_i2v_fp16_low_model = "wan2.2_i2v_A14b_low_noise_lightx2v_4step.safetensors"
        prompt["37"]["inputs"]["unet_name"] = wan22_i2v_fp16_high_model
        prompt["56"]["inputs"]["unet_name"] = wan22_i2v_fp16_low_model
        logger.info(f"using fp16 model: {wan22_i2v_fp16_high_model}, {wan22_i2v_fp16_low_model}")
    
    #Sampling: Cfg, steps, seeds
    cfg = job_input.get("cfg", 1.0)
    steps = int(job_input.get("steps", 4))
    seed = job_input.get("seed", random.randint(0, 2**32 - 1)  )
    
    low_start = int(steps*0.6)
    
    logger.info(f"cfg: {cfg}, steps: {low_start}/{steps}, seed: {seed}")
    
    prompt["57"]["inputs"]["steps"] = steps
    prompt["57"]["inputs"]["end_at_step"] = low_start
    prompt["57"]["inputs"]["cfg"] = cfg
    prompt["57"]["inputs"]["noise_seed"] = seed
    
    prompt["58"]["inputs"]["steps"] = steps
    prompt["58"]["inputs"]["start_at_step"] = low_start
    prompt["58"]["inputs"]["cfg"] = cfg
    
    # Video length, resolution (width/height) to multiples of 16
    length = job_input.get("length", 81)

    original_width = job_input.get("width", 544)
    original_height = job_input.get("height", 960)
    adjusted_width = to_nearest_multiple_of_16(original_width)
    adjusted_height = to_nearest_multiple_of_16(original_height)

    if adjusted_width != original_width:
        logger.info(f"Width adjusted to nearest multiple of 16: {original_width} -> {adjusted_width}")
    if adjusted_height != original_height:
        logger.info(f"Height adjusted to nearest multiple of 16: {original_height} -> {adjusted_height}")
    
    logger.info(f"size: {adjusted_width}x{adjusted_height}, length: {length}")
    
    prompt["83"]["inputs"]["width"] = adjusted_width
    prompt["83"]["inputs"]["height"] = adjusted_height
    prompt["83"]["inputs"]["length"] = length

    # load image path
    prompt["78"]["inputs"]["image"] = image_path
    
    # positive and negative prompt
    positive_prompt = job_input.get("prompt", "")
    negative_prompt = job_input.get("negative_prompt","slow motion")
    
    prompt["6"]["inputs"]["text"] = positive_prompt
    prompt["7"]["inputs"]["text"] = negative_prompt


    # rife vfi
    vfi_multiplier = job_input.get("vfi_multiplier", 2)
    prompt["82"]["inputs"]["multiplier"] = int(vfi_multiplier)
    
    # motion amp
    motion_amp = job_input.get("motion_amp", 1.15)
    prompt["83"]["inputs"]["motion_amplitude"] = float(motion_amp)
    
    # fps
    fps = job_input.get("fps", 27)
    prompt["81"]["inputs"]["frame_rate"] = int(fps)
    
    logger.info(f"vfi_multiplier: {vfi_multiplier}, motion_amp: {motion_amp}, fps: {fps}")
    

    ws_url = f"ws://{server_address}:8188/ws?clientId={client_id}"
    logger.info(f"Connecting to WebSocket: {ws_url}")

    # Check HTTP connection first
    http_url = f"http://{server_address}:8188/"
    logger.info(f"Checking HTTP connection to: {http_url}")

    # Check HTTP connection (up to 1 minute)
    max_http_attempts = 180
    for http_attempt in range(max_http_attempts):
        try:
            import urllib.request
            response = urllib.request.urlopen(http_url, timeout=5)
            logger.info(f"HTTP connection successful (attempt {http_attempt+1})")
            break
        except Exception as e:
            logger.warning(f"HTTP connection failed (attempt {http_attempt+1}/{max_http_attempts}): {e}")
            if http_attempt == max_http_attempts - 1:
                raise Exception("Cannot connect to ComfyUI server. Please check if the server is running.")
            time.sleep(1)

    ws = websocket.WebSocket()

    # WebSocket connection attempts (up to 3 minutes)
    max_attempts = int(180 / 5)  # 3 minutes (attempt every 5 seconds)
    for attempt in range(max_attempts):
        import time
        try:
            ws.connect(ws_url)
            logger.info(f"WebSocket connection successful (attempt {attempt+1})")
            break
        except Exception as e:
            logger.warning(f"WebSocket connection failed (attempt {attempt+1}/{max_attempts}): {e}")
            if attempt == max_attempts - 1:
                raise Exception("WebSocket connection timed out (3 minutes)")
            time.sleep(5)

    videos = get_videos(ws, prompt)
    ws.close()

    # Handle case where no image/video exists
    for node_id in videos:
        if videos[node_id]:
            return {"video": videos[node_id][0]}

    return {"error": "Could not find the video."}


runpod.serverless.start({"handler": handler})