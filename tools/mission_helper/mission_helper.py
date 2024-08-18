#%%
import dcs
import itertools
from collections import defaultdict
from util import load_mission, save_mission

DISPERSE_TIME_S = 30
KNOT_IN_MPS = 0.514444


def knots_to_mps(knots):
    return knots * KNOT_IN_MPS


def get_tasks(vehgrp):
    return vehgrp.points[0].tasks


def has_disperse_option(vehgrp):
    tasks = get_tasks(vehgrp)
    return any(isinstance(t, dcs.task.OptDisparseUnderFire) for t in tasks)


def remove_disperse_option(vehgrp):
    tasks = get_tasks(vehgrp)
    for idx, elem in enumerate(tasks):
        if isinstance(elem, dcs.task.OptDisparseUnderFire):
            del tasks[idx]


def add_task(vehgrp, task):
    tasks = get_tasks(vehgrp)
    tasks.append(task)


class MissionWrapper():

    def __init__(self, mission: dcs.Mission):
        self.m = mission
        self.all_blue = list(self.get_vehicle_groups('blue'))
        self.all_red = list(self.get_vehicle_groups('red'))

    def get_all_ground_for_side(self, side):
        return self.all_red if side == 'red' else self.all_blue

    def get_countries(self, side):
        return self.m.coalition[side].countries

    def get_vehicle_groups(self, side):
        countries = self.get_countries(side)
        return itertools.chain(*(countries[cname].vehicle_group
                                 for cname in countries))

    def get_plane_groups(self, side):
        countries = self.get_countries(side)
        return itertools.chain(*(countries[cname].plane_group
                                 for cname in countries))

    def get_unit_count(self, side='red'):
        red_unit_count = defaultdict(lambda: 0)
        groups = self.get_all_ground_for_side('red')

        for group in groups:
            units = group.units
            n = len(units)
            kind = units[0].type
            is_mixed = not all(u.type == units[0].type for u in units)
            if not group.late_activation:
                for unit in units:
                    red_unit_count[unit.type] += 1

    def set_all_units_speed(self, speed_knots=20.0, side='red'):
        speed_knots = float(speed_knots)
        groups = self.get_all_ground_for_side(side)
        for g in groups:
            points = g.points
            if len(points) > 1:
                for p in points:
                    if p.speed > 0.0001:
                        p.speed = knots_to_mps(speed_knots)

    def save(self):
        return save_mission(self.m)


def main():
    m = MissionWrapper(load_mission())
    # m.set_all_units_speed(20.0, 'red')
    # print("After modifying speeds, all red group waypoint speeds (in m/s):")
    # for group in m.all_red:
    #     print(f"{group} {[p.speed for p in group.points]}")

    blue_air = m.get_plane_groups('blue')
    for group in blue_air:
        if any(plane.skill == dcs.unitgroup.Skill.Client for plane in group.units):
            print(f"changing type for {group}")
            if group.points[0].type == 'TakeOffParking':
                print(f"current type is {group.points[0].action}")
                group.points[0].type = 'TakeOffParkingHot'
                group.points[0].action = dcs.point.PointAction.FromParkingAreaHot
    m.save()



if __name__ == '__main__':
    main()

# # %%
# mis = dcs.Mission()
# mis.load_file("C:/Users/Bobby/Saved Games/dcs/missions/gof_m01.miz")

# m = MissionWrapper(mis)
# blue_air = list(m.get_plane_groups('blue'))
# # %%
