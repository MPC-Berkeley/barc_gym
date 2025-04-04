import copy
import time
from typing import Tuple, Optional, Dict, Any, Union

import gymnasium as gym
from gymnasium.core import ActType, ObsType

from mpclab_common.pytypes import VehicleState, VehicleActuation, VehiclePrediction, Position, ParametricPose, \
    BodyLinearVelocity, OrientationEuler, BodyAngularVelocity
# from utils import data_utils
import numpy as np
# import utils.data_fitting as fit

# import gym
from gymnasium import spaces
# from utils.data_utils import DynamicsDataset as DD

# from barc_gym.mpclab_simulation.mpclab_python_simulation.utils.renderer import LMPCVisualizer
from mpclab_common.track import get_track
from mpclab_common.models.dynamics_models import CasadiDynamicBicycle, CasadiDynamicCLBicycle, DynamicBicycleConfig

from loguru import logger

from gym_carla.envs.utils.renderer import LMPCVisualizer
from gym_carla.envs.utils.lazy_renderer import LazyLMPCVisualizer
from mpclab_simulation.dynamics_simulator import DynamicsSimulator


class BarcEnv(gym.Env):
    metadata = {'render.modes': ['human']}

    def __init__(self, track_name, t0=0., dt=0.1, dt_sim=0.01, max_n_laps=100,
                 do_render=True, enable_camera=False, host='localhost', port=2000,
                 in_colab=False):
        self.track_obj = get_track(track_name)
        # self.track_obj.slack = 1
        self.t0 = t0  # Constant
        self.dt = dt
        self.dt_sim = dt_sim
        self.max_n_laps = max_n_laps
        self.do_render = do_render
        self.enable_camera = enable_camera
        self.track_name = track_name
        self.host = host
        self.port = port

        L = self.track_obj.track_length
        H = self.track_obj.half_width
        VL = 0.37
        VW = 0.195
        sim_dynamics_config = DynamicBicycleConfig(dt=dt_sim,
                                                   model_name='dynamic_bicycle',
                                                   noise=False,
                                                   discretization_method='rk4',
                                                   simple_slip=False,
                                                   tire_model='pacejka',
                                                   # mass=2.91,
                                                   # gravity=9.81,
                                                   # yaw_inertia=0.03323,
                                                   # wheel_dist_front=0.13,
                                                   # wheel_dist_rear=0.13,
                                                   # wheel_dist_center_front=0.1,
                                                   # wheel_dist_center_rear=0.1,
                                                   # bump_dist_front=0.15,
                                                   # bump_dist_rear=0.15,
                                                   # bump_dist_center=0.1,
                                                   mass=2.258,
                                                   yaw_inertia= 0.02771, #0.02723
                                                   wheel_friction=0.9,
                                                   pacejka_b_front=5.0,
                                                   pacejka_b_rear=5.575055782097995, #5.0
                                                   pacejka_c_front=2.28,
                                                   pacejka_c_rear=2.0524659447890445) #2.28)
        # dynamics_simulator = DynamicsSimulator(t, sim_dynamics_config, delay=None, track=track_obj)
        self.dynamics_simulator = DynamicsSimulator(t0, sim_dynamics_config, delay=[0.1, 0.1], track=self.track_obj)
        if enable_camera:
            from gym_carla.envs.barc.cameras.carla_bridge import CarlaConnector
            self.camera_bridge = CarlaConnector(self.track_name, host=self.host, port=self.port)
        else:
            self.camera_bridge = None

        if in_colab:
            self.visualizer = LazyLMPCVisualizer(track_obj=self.track_obj, VL=VL, VW=VW)
        else:
            self.visualizer = LMPCVisualizer(track_obj=self.track_obj, VL=VL, VW=VW)

        self.sim_state: VehicleState = None
        self.last_state: VehicleState = None

        # Additional information fields
        self.lap_speed = []
        self.v_buffer = []
        self.u_buffer = []
        self.traj = []
        self.lap_no = 0

        observation_space = dict(
            gps=spaces.Box(low=-np.inf, high=np.inf, shape=(3,), dtype=np.float32),
            velocity=spaces.Box(low=-np.inf, high=np.inf, shape=(3,), dtype=np.float32),
            state=spaces.Box(low=-np.inf, high=np.inf, shape=(6,), dtype=np.float32),
        )
        if self.enable_camera:
            from gym_carla.envs.barc.cameras.carla_bridge import CarlaConnector
            # All images are channel-first.
            observation_space.update(dict(
                camera=spaces.Box(low=0, high=255, shape=(self.camera_bridge.height, self.camera_bridge.width, 3),
                                  dtype=np.uint8),
                # depth=spaces.Box(low=0, high=255, shape=(3, H, W), dtype=np.uint8),
                # imu=spaces.Box(low=-np.inf, high=np.inf, shape=(6,), dtype=np.float64),
            ))

        self.observation_space = spaces.Dict(observation_space)
        # self.action_space = spaces.Box(low=-np.inf, high=np.inf, shape=(2,), dtype=np.float64)
        self._action_bounds = np.array([2, 0.45])
        self.action_space = spaces.Box(low=-self._action_bounds,
                                       high=self._action_bounds, dtype=np.float64)

        self.t = None
        self.max_lap_speed = self.min_lap_speed = self._sum_lap_speed = self.eps_len = 0

    def get_track(self):
        return self.track_obj

    def bind_controller(self, controller):
        self.visualizer.bind_controller(controller)

    def clip_action(self, action):
        return np.clip(action, -self._action_bounds, self._action_bounds)

    def _is_new_lap(self):
        def orientation(p, q, r):
            val = (q[1] - p[1]) * (r[0] - q[0]) - (q[0] - p[0]) * (r[1] - q[1])
            if val == 0:
                return 0  # Collinear
            return 1 if val > 0 else 2  # Clockwise or Counterclockwise

        def on_segment(p, q, r):
            return (min(p[0], r[0]) <= q[0] <= max(p[0], r[0]) and
                    min(p[1], r[1]) <= q[1] <= max(p[1], r[1]))

        def do_intersect(p1, q1, p2, q2):
            o1 = orientation(p1, q1, p2)
            o2 = orientation(p1, q1, q2)
            o3 = orientation(p2, q2, p1)
            o4 = orientation(p2, q2, q1)

            # General case
            if o1 != o2 and o3 != o4:
                return True

            # Special cases
            if o1 == 0 and on_segment(p1, p2, q1):
                return True
            if o2 == 0 and on_segment(p1, q2, q1):
                return True
            if o3 == 0 and on_segment(p2, p1, q2):
                return True
            if o4 == 0 and on_segment(p2, q1, q2):
                return True

            return False

        return do_intersect(np.array([self.sim_state.x.x, self.sim_state.x.y]),
                            np.array([self.last_state.x.x, self.last_state.x.y]),
                            np.array([0, self.track_obj.half_width]),
                            np.array([0, -self.track_obj.half_width]))

    def reset(
            self,
            *,
            seed: Optional[int] = None,
            options: Optional[dict] = None,
    ) -> Tuple[ObsType, dict]:
        if seed is not None:
            np.random.seed(seed)
        if (options is not None and options.get('render')) or self.do_render:
            self.visualizer.reset()
        elif self.visualizer is not None:
            self.visualizer.close()
        if options.get('spawning') == 'fixed':
            logger.debug("Respawning at fixed location.")
            self.sim_state = VehicleState(t=0.0,
                                          p=ParametricPose(s=0.1, x_tran=0),
                                          e=OrientationEuler(psi=0),
                                          v=BodyLinearVelocity(v_long=0.5, v_tran=0),
                                          w=BodyAngularVelocity(w_psi=0))
        else:
            self.sim_state = VehicleState(t=0.0,
                                          p=ParametricPose(s=np.random.uniform(0.1, self.track_obj.track_length - 2),
                                                           x_tran=np.random.uniform(
                                                               -self.track_obj.half_width - self.track_obj.slack,
                                                               self.track_obj.half_width + self.track_obj.slack),
                                                           e_psi=np.random.uniform(-np.pi / 6, np.pi / 6), ),
                                          # e=OrientationEuler(psi=0),
                                          v=BodyLinearVelocity(v_long=np.random.uniform(0.5, 2), v_tran=0),
                                          w=BodyAngularVelocity(w_psi=0))
        self.track_obj.local_to_global_typed(self.sim_state)
        self.last_state = copy.deepcopy(self.sim_state)

        self.t = self.t0
        self.lap_start = self.t
        self.lap_speed = []

        self.lap_no = 0

        self._reset_speed_stats()
        self.eps_len = 1

        obs, info = self._get_obs(), self._get_info()
        self.traj = [obs['gps'].copy()]
        self.v_buffer = [obs['velocity'].copy()]
        self.u_buffer = []

        return obs, info

    def _update_speed_stats(self):
        v = np.linalg.norm([self.sim_state.v.v_long, self.sim_state.v.v_tran])
        self.max_lap_speed = max(self.max_lap_speed, v)
        self.min_lap_speed = min(self.min_lap_speed, v)
        self._sum_lap_speed += v
        self.eps_len += 1

    def _reset_speed_stats(self):
        v = np.linalg.norm([self.sim_state.v.v_long, self.sim_state.v.v_tran])
        self.max_lap_speed = self.min_lap_speed = self._sum_lap_speed = v

    def step(self, action: ActType) -> Tuple[ObsType, float, bool, bool, dict]:
        action = np.clip(action, -self._action_bounds, self._action_bounds)
        self.sim_state.u.u_a, self.sim_state.u.u_steer = action
        self.last_state = copy.deepcopy(self.sim_state)
        # self.sim_state.copy_control(action)
        self.render()

        truncated = False
        try:
            self.dynamics_simulator.step(self.sim_state, T=self.dt)
            # _slack, self.track_obj.slack = self.track_obj.slack, 0.5
            self.track_obj.global_to_local_typed(self.sim_state)
            # self.track_obj.slack = _slack
            # TODO: Future - replace the dynamics_simulator with other dynamics functions. (e.g. data-driven models)
        except ValueError as e:
            truncated = True  # The control action may drive the vehicle out of the track during the internal steps. Process the exception here immediately.

        self.t += self.dt
        self._update_speed_stats()

        obs = self._get_obs()
        rew = self._get_reward()
        terminated = self._get_terminal()
        truncated = truncated or self._get_truncated()
        info = self._get_info()

        self.traj.append(obs['gps'].copy())
        self.v_buffer.append(obs['velocity'].copy())
        self.u_buffer.append(action.copy())

        if terminated:
            logger.info(
                f"Lap {self.lap_no} finished in {info['lap_time']:.1f} s. "
                f"avg_v = {info['avg_lap_speed']:.4f}, max_v = {info['max_lap_speed']:.4f}, "
                f"min_v = {info['min_lap_speed']:.4f}")
            self.lap_no += 1
            self.lap_start = self.t
            self._reset_speed_stats()
            self.eps_len = 1

        return obs, rew, terminated, truncated, info

    def show_debug_plot(self, axes=None):
        from matplotlib import pyplot as plt
        traj = np.asarray(self.traj)
        v_buffer = np.asarray(self.v_buffer)
        u_buffer = np.asarray(self.u_buffer)

        if axes is not None:
            ((ax_traj, ax_v), (ax_u_a, ax_u_d)) = axes
        else:
            fig, ((ax_traj, ax_v), (ax_u_a, ax_u_d)) = plt.subplots(2, 2, figsize=(9, 9))

        self.get_track().plot_map(ax=ax_traj)
        ax_traj.plot(traj[:, 0], traj[:, 1], label='simulated')
        ax_traj.set_aspect('equal')
        ax_traj.set_title("Trajectory playback")
        ax_traj.set_xlabel('x(m)')
        ax_traj.set_ylabel('y(m)')

        ax_v.plot(np.arange(v_buffer.shape[0]) * self.dt, v_buffer[:, 0], label='simulated')
        ax_v.set_xlabel('t(s)')
        ax_v.set_ylabel('v(m/s)')
        ax_v.set_title("Velocity playback")

        ax_u_a.plot(np.arange(u_buffer.shape[0]) * self.dt, u_buffer[:, 0], label='simulated')
        ax_u_a.set_xlabel('t(s)')
        ax_u_a.set_label('$u_a$')
        ax_u_a.set_title("Acceleration input playback")

        ax_u_d.plot(np.arange(u_buffer.shape[0]) * self.dt, u_buffer[:, 1], label='simulated')
        ax_u_d.set_xlabel('t(s)')
        ax_u_d.set_ylabel('$u_{steer}$')
        ax_u_d.set_title("Steering input playback")

        # plt.show()

    def render(self):
        if not self.do_render:
            return
        self.visualizer.step(self.sim_state)

    def _get_obs(self) -> Dict[str, np.ndarray]:
        ob = {
            'gps': np.array([self.sim_state.x.x, self.sim_state.x.y, self.sim_state.e.psi], dtype=np.float32),
            'velocity': np.array([self.sim_state.v.v_long, self.sim_state.v.v_tran, self.sim_state.w.w_psi],
                                 dtype=np.float32),
            'state': np.array([self.sim_state.v.v_long, self.sim_state.v.v_tran, self.sim_state.w.w_psi,
                               self.sim_state.p.s, self.sim_state.p.x_tran, self.sim_state.p.e_psi], dtype=np.float32),
            # self.sim_state.x.x, self.sim_state.x.y, self.sim_state.e.psi], dtype=np.float32),
            # For backward compatibility.
        }
        if self.enable_camera:
            while True:
                try:
                    camera = self.camera_bridge.query_rgb(self.sim_state)
                    break
                except RuntimeError as e:
                    logger.error(e)
                from gym_carla.envs.barc.cameras.carla_bridge import CarlaConnector
                while True:
                    time.sleep(10)
                    try:
                        self.camera_bridge = CarlaConnector(self.track_name, self.host, self.port)
                        break
                    except RuntimeError as e:
                        logger.error(e)
            ob.update({
                'camera': camera,
                # 'depth': None,
                # 'imu': None,
            })
        return ob

    def _get_reward(self) -> float:
        ds = self.sim_state.p.s - self.last_state.p.s
        if self._is_new_lap() and self.sim_state.p.s < self.last_state.p.s:
            ds += self.track_obj.track_length
        return ds
        # return 0

    def _get_terminal(self) -> bool:
        """
        Note: Now `terminated` means the beginning of a new lap.
        To collect long trajectories, this should NOT be used to reset the rollout.
        Instead, use this as a trigger to e.g. update the expert.
        """
        return self._is_new_lap() and self.sim_state.p.s < self.last_state.p.s

    def _get_truncated(self) -> bool:
        """
        Note: Now `truncated` means constraint violation or maximum lap reached.
        This should be used for truncating the rollout (resetting the simulation).
        """
        conditions = [
            np.abs(self.sim_state.p.x_tran) > self.track_obj.half_width,  # Out of track.
            self.lap_no >= self.max_n_laps,  # Maximum lap number reached.
            self.sim_state.v.v_long < 0.25,
            np.abs(self.sim_state.p.e_psi) > np.pi / 2,
        ]
        return any(conditions)

    def _get_info(self) -> Dict[str, Union[VehicleState, int, float]]:
        return {
            'vehicle_state': copy.deepcopy(self.sim_state),  # Ground truth vehicle state.
            'lap_no': self.lap_no,  # Lap number
            'terminated': self._get_terminal(),
            'avg_lap_speed': self._sum_lap_speed / self.eps_len,  # Mean velocity of the current lap.
            'max_lap_speed': self.max_lap_speed,  # Max velocity of the current lap.
            'min_lap_speed': self.min_lap_speed,  # Min velocity of the current lap.
            'lap_time': self.eps_len * self.dt,  # Time elapsed so far in the current lap.
        }
