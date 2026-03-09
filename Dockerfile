FROM wlsdml1114/engui_genai-base_blackwell:1.1 as runtime

RUN pip install -U "huggingface_hub[hf_transfer]"

WORKDIR /

RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    cd ComfyUI-VideoHelperSuite && \
    pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
	
RUN mkdir -p /ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife && wget https://huggingface.co/hfmaster/models-moved/resolve/cab6dcee2fbb05e190dbb8f536fbdaa489031a14/rife/rife49.pth -q -O /ComfyUI/custom_nodes/ComfyUI-Frame-Interpolation/ckpts/rife/rife49.pth

RUN cd /ComfyUI/custom_nodes && \
    git clone https://github.com/princepainter/ComfyUI-PainterI2V.git
	
RUN rm -rf /ComfyUI/models/diffusion_models && \
    rm -rf /ComfyUI/models/loras && \
    rm -rf /ComfyUI/models/text_encoders && \
    rm -rf /ComfyUI/models/vae && \
    ln -s /runpod-volume/TI2V_4steps/diffusion_models /ComfyUI/models/diffusion_models && \
    ln -s /runpod-volume/TI2V_4steps/loras /ComfyUI/models/loras && \
    ln -s /runpod-volume/TI2V_4steps/text_encoders /ComfyUI/models/text_encoders && \
    ln -s /runpod-volume/TI2V_4steps/vae /ComfyUI/models/vae

RUN pip install sageattention runpod websocket-client


COPY . .

RUN chmod +x /start.sh

CMD ["/start.sh"]