#!/bin/python3

import os
import subprocess

from typing import Iterable, List

common_options = [
    '-parallel',
    '-tex_array', '-tex_type', '2darray',
    '-mipmap', '-mip_clamp', '-mip_smallest', '16',
]

def srgb_command(inputs: Iterable[str], output_path: str) -> List[str]:
    return ['basisu'] + inputs + common_options + ['-output_path', output_path]

def normal_map_command(inputs: Iterable[str], output_path: str) -> List[str]:
    extra_options = [
        '-normal_map', '-linear', '-renorm', '-mip_renorm',
    ]
    return ['basisu'] + inputs + common_options + extra_options + ['-output_path', output_path]

def make_input_file_paths(material_dirs: Iterable[str], texture_name: str) -> List[str]:
    return [os.path.join(d, texture_name) for d in material_dirs]

def srgb_array_command(
    material_dirs: Iterable[str],
    texture_name: str,
    output_path: str
) -> List[str]:
    input_files = make_input_file_paths(material_dirs, texture_name)
    return srgb_command(input_files, output_path)

def normal_map_array_command(
    material_dirs: Iterable[str],
    output_path: str
) -> List[str]:
    input_files = make_input_file_paths(material_dirs, 'normal.png')
    return normal_map_command(input_files, output_path)


material_dirs = [
    'angled-blocks-vegetation-ue.converted',
    'broken-down-stonework1-ue.converted',
    'sand-dunes1-ue.converted',
    'ice_field.converted',
]
output_dir = 'array_material'

subprocess.run(normal_map_array_command(material_dirs, output_dir))
subprocess.run(srgb_array_command(material_dirs, 'albedo.png', output_dir))
subprocess.run(srgb_array_command(material_dirs, 'ao.png', output_dir))
subprocess.run(srgb_array_command(material_dirs, 'metal_rough.png', output_dir))
