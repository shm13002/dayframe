"""Fine-tunes the Piper Jarvis voice on this Mac. Run it with ~/jarvis-piper/.venv/bin/python.

It wraps `python -m piper.train fit` with three changes for this Mac:
  - Only one checkpoint is kept (last.ckpt, about 846 MB). Piper's defaults keep up to eleven,
    which would fill this disk.
  - Every training step's time and the peak memory go to --steps-log, so a run can be judged
    in its first minutes.
  - The MOS metric is off, because it would download a UTMOS model through torch.hub.
Every other argument goes straight to piper.train, for example:

  python train.py --steps-log ~/jarvis-piper/train-steps.log --checkpoint-every 5 \
      --data.voice_name jarvis --data.csv_path … --data.audio_dir … --model.sample_rate 22050 \
      --data.espeak_voice en-gb --data.cache_dir … --data.config_path … --data.batch_size 16 \
      --ckpt_path …
"""

import argparse
import resource
import sys
import time
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--steps-log", required=True)
    parser.add_argument(
        "--checkpoint-every",
        type=int,
        default=5,
        help="epochs between saves of last.ckpt; 0 never saves (speed probes)",
    )
    ours, rest = parser.parse_known_args()

    from lightning.pytorch.callbacks import Callback, ModelCheckpoint

    import piper.train.__main__ as piper_train

    class StepLog(Callback):
        """One line per training batch: when, which epoch and batch, seconds since the last one."""

        def __init__(self, path: str) -> None:
            self.path = Path(path).expanduser()
            self.last = None

        def on_train_batch_start(self, trainer, pl_module, batch, batch_idx) -> None:
            if self.last is None:
                self.last = time.perf_counter()

        def on_train_batch_end(self, trainer, pl_module, outputs, batch, batch_idx) -> None:
            now = time.perf_counter()
            # ru_maxrss is in bytes on macOS.
            peak_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1_048_576
            with self.path.open("a") as log:
                log.write(
                    f"{time.strftime('%H:%M:%S')} epoch={trainer.current_epoch} "
                    f"batch={batch_idx} seconds={now - self.last:.2f} peak_mb={peak_mb:.0f}\n"
                )
            self.last = now

    callbacks = [StepLog(ours.steps_log)]
    extra = []
    if ours.checkpoint_every > 0:
        callbacks.append(
            ModelCheckpoint(save_top_k=0, save_last=True, every_n_epochs=ours.checkpoint_every)
        )
    else:
        extra.append("--trainer.enable_checkpointing=false")
    if not any(arg.startswith("--model.mos_metric") for arg in rest):
        extra.append("--model.mos_metric=none")

    # piper.train reads this list when it builds the trainer, so replacing its contents here
    # replaces Piper's checkpoint callbacks.
    piper_train._DEFAULT_CALLBACKS[:] = callbacks
    sys.argv = [sys.argv[0], *rest, *extra]
    piper_train.main()


if __name__ == "__main__":
    main()
