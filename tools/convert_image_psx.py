import argparse
import struct
import pathlib
from typing import Any, cast
from PIL import Image
import imagequant
import numpy as np
from numpy import ndarray

MIN_VISIBLE_ALPHA: int = 32
MIN_OPAQUE_ALPHA: int = 192

parser = argparse.ArgumentParser(description = "Convert images for sm64-psx")
parser.add_argument("input", type = Image.open)
parser.add_argument("output", type = pathlib.Path)
parser.add_argument("-b", type = int, required = True, help = "output bit depth (4/8/16)")
args = parser.parse_args()

bit_depth: int = args.b
assert bit_depth in (4, 8, 16)

img_rotated = False
has_translucency = False
rgba_arr: np.typing.NDArray[np.int_]

with args.input as image:
	image: Image.Image
	image.load()

	if image.mode != "RGBA":
		image = image.convert("RGBA")

	if image.width % 2 != 0:
		image = image.transform((image.width + 1, image.height), Image.Transform.EXTENT, (0, 0, image.width, image.height))

	if image.width == 32 and image.height == 64:
		w, h = image.size
		rotated_pixels: list[Any] = []
		for x in range(0, image.width):
			for y in range(0, image.height):
				rotated_pixels.append(image.getpixel((x, y)))
		newImage = Image.new(image.mode, (h, w))
		i = 0
		for y in range(0, newImage.height):
			for x in range(0, newImage.width):
				newImage.putpixel((x, y), rotated_pixels[i])
				i += 1
		image = newImage
		img_rotated = True

	rgba_arr = np.asarray(image)
	width = image.width
	height = image.height

r5_arr = (np.astype(rgba_arr[:, :, 0], np.uint16) + 4) >> 3
g5_arr = (np.astype(rgba_arr[:, :, 1], np.uint16) + 4) >> 3
b5_arr = (np.astype(rgba_arr[:, :, 2], np.uint16) + 4) >> 3
psx_arr = r5_arr | g5_arr << 5 | b5_arr << 10
alpha_arr = rgba_arr[:, :, 3]

black_pixels = psx_arr == 0
visible_pixels = alpha_arr >= MIN_VISIBLE_ALPHA
opaque_pixels = alpha_arr >= MIN_OPAQUE_ALPHA

has_translucency = np.logical_and(visible_pixels, np.logical_not(opaque_pixels)).any()

if has_translucency:
	psx_arr = np.select(
		(
			np.logical_and(opaque_pixels, black_pixels),
			opaque_pixels,
			visible_pixels
		), (
			np.array(1 | 1 << 5 | 1 << 10, np.uint16),
			psx_arr,
			psx_arr | 0x8000
		),
		0
	)
else:
	psx_arr = np.where(visible_pixels, psx_arr | 0x8000, 0)

def make_palette(max_colors: int) -> list[int]:
	unique, counts = np.unique(psx_arr, return_counts = True)
	palette = list(unique[np.argsort(counts)[::-1][:max_colors]])
	while len(palette) < 16:
		palette.append(0)
	return palette

output_bytes = bytearray()
output_bytes.extend(width.to_bytes(2, "little"))
output_bytes.extend(height.to_bytes(2, "little"))
output_bytes.append(1 if img_rotated else 0)
output_bytes.append(1 if has_translucency else 0)
output_bytes.extend(b"\0\0\0\0\0\0\0\0\0\0")

match bit_depth:
	case 4:
		winning_indices = np.array(tuple(tuple(0 for _ in range(width)) for _ in range(height)), dtype = np.uint8)
		winning_distances = np.array(tuple(tuple(65535 for _ in range(width)) for _ in range(height)), dtype = np.uint16)
		pixel_distances = []
		palette = make_palette(16)
		for color_idx, color_value in enumerate(palette):
			output_bytes.append(color_value & 0xFF)
			output_bytes.append(color_value >> 8)
			if color_value == 0:
				winning_indices = np.where(visible_pixels, winning_indices, color_idx)
				winning_distances = np.where(visible_pixels, winning_indices, 0)
			else:
				r = color_value & 0x1F
				g = color_value >> 5 & 0x1F
				b = color_value >> 10 & 0x1F
				distances_to_this_color = np.array(np.sqrt(np.square(np.abs(r5_arr - r)) + np.square(np.abs(g5_arr - g)) + np.square(np.abs(b5_arr - b))), dtype = np.uint16)
				winning_indices = np.where(
					np.logical_and(visible_pixels, distances_to_this_color < winning_distances),
					color_idx,
					winning_indices
				)

		for y in range(height):
			for x in range(0, width, 2):
				output_bytes.append(winning_indices[y][x] | winning_indices[y][x + 1] << 4)
	#case 8:
	#	indices, psx_palette_bytes = quantize(256)
	#	output_bytes.extend(psx_palette_bytes)
	#	for _ in range(256 * 2 - len(psx_palette_bytes)):
	#		output_bytes.append(0)
	#	for palette_index in indices:
	#		output_bytes.append(palette_index)
	case 16:
		output_bytes.extend(rgba_to_psx16_bytes(rgba_bytes))

with open(args.output, "wb") as output:
	output.write(output_bytes)
