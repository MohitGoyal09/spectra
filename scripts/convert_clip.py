"""Converts OpenAI CLIP ViT-B/32 (MIT licence) to two Core ML models for on-device picture search.

    uv venv --python 3.12 .clipenv && VIRTUAL_ENV=.clipenv uv pip install torch==2.5.1 transformers==4.46.3 coremltools==8.1 numpy==1.26.4 pillow
    .clipenv/bin/python scripts/convert_clip.py App/Resources/Models

Writes ClipImage.mlpackage (224x224 RGB image -> 512 unit vector) and ClipText.mlpackage (77 int32 token ids -> 512 unit vector).
Weights are 8-bit quantized (~150 MB total). Image normalization is baked into the model.
"""
import sys, os
import numpy as np
import torch
import coremltools as ct
import coremltools.optimize.coreml as cto
from transformers import CLIPModel, CLIPTokenizer, CLIPProcessor
from PIL import Image

REPO, REV = "openai/clip-vit-base-patch32", "3d74acf9a28c67741b2f4f2ea7635f0aaf6f0268"
MEAN = torch.tensor([0.48145466, 0.4578275, 0.40821073]).view(1, 3, 1, 1)
STD = torch.tensor([0.26862954, 0.26130258, 0.27577711]).view(1, 3, 1, 1)


class ImageEncoder(torch.nn.Module):
    def __init__(self, m):
        super().__init__(); self.v, self.p = m.vision_model, m.visual_projection
    def forward(self, image):                      # image: 0...1 RGB, (1, 3, 224, 224)
        e = self.p(self.v(pixel_values=(image - MEAN) / STD).pooler_output)
        return e / e.norm(dim=-1, keepdim=True)


class TextEncoder(torch.nn.Module):
    def __init__(self, m):
        super().__init__(); self.t, self.p = m.text_model, m.text_projection
    def forward(self, ids):                        # ids: (1, 77) int32, end token 49407 then padding
        e = self.p(self.t(input_ids=ids.long()).pooler_output)
        return e / e.norm(dim=-1, keepdim=True)


def convert(module, example, inputs, name, out_dir):
    traced = torch.jit.trace(module, example)
    model = ct.convert(traced, inputs=inputs, outputs=[ct.TensorType(name="embedding")],
                       minimum_deployment_target=ct.target.iOS18, compute_precision=ct.precision.FLOAT16)
    model = cto.linear_quantize_weights(model, cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric")))
    model.short_description = "OpenAI CLIP ViT-B/32 (MIT), converted for TidyRoll picture search"
    path = os.path.join(out_dir, f"{name}.mlpackage"); model.save(path)
    return model


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    m = CLIPModel.from_pretrained(REPO, revision=REV).eval()
    tok = CLIPTokenizer.from_pretrained(REPO, revision=REV)
    img = ImageEncoder(m).eval(); txt = TextEncoder(m).eval()
    ex_img = torch.rand(1, 3, 224, 224)
    ex_ids = torch.tensor([tok("a photo of a dog", padding="max_length", max_length=77)["input_ids"]], dtype=torch.int32)
    ci = convert(img, ex_img, [ct.ImageType(name="image", shape=(1, 3, 224, 224), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)], "ClipImage", out_dir)
    ct_ = convert(txt, ex_ids, [ct.TensorType(name="ids", shape=(1, 77), dtype=np.int32)], "ClipText", out_dir)

    # Check: Core ML matches PyTorch, and a dog photo prefers "dog" text over "receipt".
    pil = Image.new("RGB", (224, 224)); arr = np.random.RandomState(0).randint(0, 255, (224, 224, 3), dtype=np.uint8); pil = Image.fromarray(arr)
    with torch.no_grad():
        ref_i = img(torch.from_numpy(arr).permute(2, 0, 1).unsqueeze(0).float() / 255).numpy()[0]
        ref_t = txt(ex_ids).numpy()[0]
    got_i = ci.predict({"image": pil})["embedding"].reshape(-1)
    got_t = ct_.predict({"ids": ex_ids.numpy()})["embedding"].reshape(-1)
    print("image cosine vs torch:", float(np.dot(ref_i, got_i) / np.linalg.norm(got_i)))
    print("text cosine vs torch:", float(np.dot(ref_t, got_t) / np.linalg.norm(got_t)))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "App/Resources/Models")
