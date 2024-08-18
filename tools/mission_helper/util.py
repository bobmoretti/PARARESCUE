import os
import tempfile
import shutil
import dcs

MIZ_FILE_NAME = "GoF_M01_1.0"

from contextlib import contextmanager


@contextmanager
def make_tempdir():
    temp_dir = tempfile.mkdtemp()
    try:
        yield temp_dir
    finally:
        shutil.rmtree(temp_dir)


def find_dir_in_parent(test, dirs=(MIZ_FILE_NAME, )):
    prev, test = None, os.path.abspath(test)
    while prev != test:
        if any(os.path.isdir(os.path.join(test, d)) for d in dirs):
            return test
        prev, test = test, os.path.abspath(os.path.join(test, os.pardir))
    raise ValueError(f"{dirs} not found in parent path")


def load_mission(filename: str = MIZ_FILE_NAME) -> dcs.Mission:
    mission_parent_dir = find_dir_in_parent(os.getcwd(), (filename,))
    mission_dir = os.path.join(mission_parent_dir, filename)
    m = dcs.Mission()
    with make_tempdir() as tmp_dir:
        outfile_name = os.path.join(tmp_dir, filename)
        shutil.make_archive(outfile_name, format='zip', root_dir=mission_dir)
        m.load_file(outfile_name + '.zip')
    return m


def save_mission(mission: dcs.Mission, filename: str = MIZ_FILE_NAME):
    mission_parent_dir = find_dir_in_parent(os.getcwd(), filename)
    mission_dir = os.path.join(mission_parent_dir, filename)

    with make_tempdir() as tmp_dir:
        outfile_name = os.path.join(tmp_dir, filename)
        mission.save(outfile_name)
        shutil.unpack_archive(outfile_name, mission_dir, format='zip')

