"""Runs only in the user's official model environment; never in the iPhone app."""
import sys
import numpy as np
import torch


def main():
    engine, source, target, model_path, device = sys.argv[1:]
    if engine == "depth-anything-3":
        from depth_anything_3.api import DepthAnything3
        model = DepthAnything3.from_pretrained(model_path, local_files_only=True).to(device).eval()
        with torch.inference_mode():
            values = model.inference([source]).depth[0]
    elif engine == "depth-pro":
        import depth_pro
        model, transform = depth_pro.create_model_and_transforms(device=torch.device(device))
        model.eval()
        image, _, focal = depth_pro.load_rgb(source)
        with torch.inference_mode():
            values = model.infer(transform(image), f_px=focal)["depth"].detach().cpu().numpy()
    else:
        raise ValueError("Unsupported engine")
    np.save(target, np.asarray(values, dtype=np.float32), allow_pickle=False)


if __name__ == "__main__":
    main()
