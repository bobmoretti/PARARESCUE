import os
import shutil
from glob import glob
import argparse


def find_dcs_directory():
    home = os.environ['USERPROFILE']
    saved_games = os.path.join(home, 'Saved Games')
    dcs_openbeta = os.path.join(saved_games, 'DCS.openbeta')
    dcs = os.path.join(saved_games, 'DCS')
    candidate_dcs_dirs = [dcs_openbeta, dcs]
    for candidate_dcs_path in candidate_dcs_dirs:
        if os.path.exists(candidate_dcs_path):
            return candidate_dcs_path
    raise ValueError("Cannot find DCS saved games directory")


def get_dcs_missions_dir():
    dcs_dir = find_dcs_directory()
    missions_dir = os.path.join(dcs_dir, 'Missions')
    return missions_dir


def canonical_path(p):
    return os.path.normpath(os.path.abspath(p))


def main():
    parser = argparse.ArgumentParser(
        description='Pack/unpack DCS mission from/to the git repo.')
    command_group = parser.add_mutually_exclusive_group(required=True)
    command_group.add_argument(
        '--pack',
        action='store_true',
        help='Pack the miz file and copy to DCS saved games dir')

    command_group.add_argument(
        '--unpack',
        action='store_true',
        help='Extract the contents of the miz file from the DCS saved ' +
        'games dir to the local repo.')
    parser.add_argument(
        '-d',
        '--directory',
        nargs='?',
        const=os.getcwd(),
        help="If specified, copy the mission file into this directory.")

    parser.add_argument(
        '-f',
        '--force',
        action='store_true',
        default=False,
        help='Overwrite uncommitted changes when unpacking the mission')
    args = parser.parse_args()

    miz_subdir = 'PARARESCUE'
    mizname = 'PARARESCUE'
    miz_fullname = mizname + '.miz'
    miz_fullpath = canonical_path(miz_fullname)

    use_default_dir = args.directory is None
    missions_dir = get_dcs_missions_dir(
    ) if use_default_dir else args.directory
    missions_dir = canonical_path(missions_dir)
    if not os.path.exists(missions_dir):
        os.makedirs(missions_dir)
    if not os.path.isdir(missions_dir):
        raise ValueError(f"{missions_dir} is not a directory")
    miz_in_missions_dir = canonical_path(
        os.path.join(missions_dir, miz_fullname))
    miz_local = os.path.join(os.getcwd(), miz_fullname)

    def pack():
        shutil.make_archive(mizname, format='zip', root_dir=miz_subdir)
        shutil.move(mizname + '.zip', miz_fullpath)
        if os.path.exists(miz_in_missions_dir):
            shutil.copyfile(dst=miz_in_missions_dir + '.backup',
                            src=miz_in_missions_dir)
        if miz_in_missions_dir != miz_fullpath:
            shutil.copyfile(dst=miz_in_missions_dir, src=miz_fullpath)
            os.remove(miz_local)

    def unpack():
        try:
            import git
        except ImportError:
            pass
        else:
            repo = git.Repo(os.getcwd())
            if not args.force and repo.is_dirty():
                print(
                    "Found untracked local changes, please commit or discard" +
                    " before unpacking mission.")
                exit(-1)

        if miz_in_missions_dir != miz_fullname:
            shutil.copyfile(src=miz_in_missions_dir, dst=miz_fullname)
            shutil.unpack_archive(miz_fullname, miz_subdir, format='zip')
            os.remove(miz_local)

    if args.pack:
        pack()
    elif args.unpack:
        unpack()
    else:
        assert (False)


if __name__ == '__main__':
    main()
