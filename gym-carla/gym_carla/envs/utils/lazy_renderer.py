from collections import deque

import numpy as np
from matplotlib import pyplot as plt, patches
from matplotlib.animation import FuncAnimation
from matplotlib.transforms import Affine2D

# from IPython.display import HTML


class LazyLMPCVisualizer:
    def __init__(self, track_obj, VL=0.37, VW=0.195, BUFFER_MAXLEN=50):
        self.VL, self.VW = VL, VW
        self.BUFFER_MAXLEN = BUFFER_MAXLEN
        self.track_obj = track_obj
        self.enabled = False
        self.controller = None
        self.camera = None

    def initialize(self):
        # plt.ion()
        # self.v_data = deque([], maxlen=self.BUFFER_MAXLEN)
        # self.a_data = deque([], maxlen=self.BUFFER_MAXLEN)
        # self.d_data = deque([], maxlen=self.BUFFER_MAXLEN)
        self.v_data = []
        self.a_data = []
        self.d_data = []

        self.l_pred_buffer = []
        self.l_ss_buffer = []
        self.l_pa_buffer = []
        self.l_pd_buffer = []
        self.l_v_buffer = []
        self.l_a_buffer = []
        self.l_d_buffer = []
        self.rect_xy_buffer = []
        self.rect_trans_buffer = []

    def bind_controller(self, controller):
        self.controller = controller

    def step(self, state=None, *, q=None, u=None, pred=None, ss=None):
        if state is not None:
            x, y, psi = self.track_obj.local_to_global((state.p.s, state.p.x_tran, state.p.e_psi))
            v_long, v_tran, w_psi = state.v.v_long, state.v.v_tran, state.w.w_psi
            u_a, u_steer = state.u.u_a, state.u.u_steer
        elif q is not None:
            v_long, v_tran, w_psi, x, y, psi = q
            u_a, u_steer = u
        else:
            raise ValueError("Must provide either state or q")

        if self.controller is not None:
            pred = self.controller.get_prediction()
            ss = self.controller.get_safe_set()

        b_left = x - self.VL / 2
        b_bot = y - self.VW / 2
        r = Affine2D().rotate_around(x, y, psi)  # + self.ax_xy.transData

        self.rect_xy_buffer.append((b_left, b_bot))
        self.rect_trans_buffer.append(r)
        pred_x, pred_y, ss_x, ss_y = [], [], [], []

        # Plot the predictions
        if pred is not None:
            if pred.x is not None:
                pred_x, pred_y = pred.x, pred.y
            else:
                for i in range(len(pred.s)):
                    x, y, psi = self.track_obj.local_to_global((pred.s[i], pred.x_tran[i], pred.e_psi[i]))
                    pred_x.append(x)
                    pred_y.append(y)
            self.l_pred_buffer.append((pred_x, pred_y))
            self.l_pa_buffer.append((np.arange(len(self.a_data), len(self.a_data) + len(pred.u_a)), pred.u_a))
            self.l_pd_buffer.append((np.arange(len(self.d_data), len(self.d_data) + len(pred.u_steer)), pred.u_steer))

        # Plot the safety set (red squares)
        if ss is not None:
            # for i in range(len(ss.s)):
            #     x, y, psi = self.track_obj.local_to_global((ss.s[i], ss.x_tran[i], ss.e_psi[i]))
            for s_i, x_tran_i, e_psi_i in zip(ss.s, ss.x_tran, ss.e_psi):
                x, y, psi = self.track_obj.local_to_global((s_i, x_tran_i, e_psi_i))
                ss_x.append(x)
                ss_y.append(y)
            self.l_ss_buffer.append((ss_x, ss_y))

        self.v_data.append(v_long)
        self.a_data.append(u_a)
        self.d_data.append(u_steer)
        # self.l_v_buffer.append((np.arange(len(self.v_data)), np.array(self.v_data)))
        # self.l_a_buffer.append((np.arange(len(self.a_data)), np.array(self.a_data)))
        # self.l_d_buffer.append((np.arange(len(self.d_data)), np.array(self.d_data)))

        # self.fig.canvas.draw()
        # self.fig.canvas.flush_events()

    def get_animation(self):
        self.fig = plt.figure(figsize=(15, 10))
        self.ax_xy = self.fig.add_subplot(1, 2, 1)
        self.ax_v = self.fig.add_subplot(3, 2, 2)
        self.ax_a = self.fig.add_subplot(3, 2, 4)
        self.ax_d = self.fig.add_subplot(3, 2, 6)

        has_prediction = self.controller.get_prediction() is not None
        has_ss = self.controller.get_safe_set() is not None

        def init():
            self.track_obj.plot_map(self.ax_xy)
            self.ax_xy.set_aspect('equal')
            self.l_v = self.ax_v.plot([], [], '-bo')[0]
            self.l_a = self.ax_a.plot([], [], '-bo')[0]
            self.l_d = self.ax_d.plot([], [], '-bo')[0]
            self.rect = patches.Rectangle((-0.5 * self.VL, -0.5 * self.VW), self.VL, self.VW, linestyle='solid', color='b',
                                          alpha=0.5)
            self.ax_xy.add_patch(self.rect)
            self.ax_a.set_ylabel('long in')
            self.ax_d.set_ylabel('lat in')
            self.ax_v.set_ylabel('long vel')
            self.ax_d.set_xlabel('time steps')
            self.ax_v.set_xlim(0, 50)
            self.ax_a.set_xlim(0, 50)
            self.ax_d.set_xlim(0, 50)
            self.ax_v.set_ylim(0, max(self.v_data) + 0.5)
            self.ax_a.set_ylim(min(self.a_data) - 0.5, max(self.a_data) + 0.5)
            self.ax_d.set_ylim(min(self.d_data) - 0.5, max(self.d_data) + 0.5)

            artists = [self.l_v, self.l_a, self.l_d, self.rect]

            if has_prediction:
                self.l_pred = self.ax_xy.plot([], [], 'b-o', markersize=4)[0]
                self.l_pa = self.ax_a.plot([], [], '-go')[0]
                self.l_pd = self.ax_d.plot([], [], '-go')[0]
                artists.extend((self.l_pred, self.l_pa, self.l_pd))
            if has_ss:
                self.l_ss = self.ax_xy.plot([], [], 'rs', markersize=4, markerfacecolor='None')[0]
                artists.append(self.l_ss)
            return tuple(artists)

        def update(i):
            self.l_v.set_data(np.arange(min(50, i + 1)), self.v_data[max(0, i - 49): i + 1])
            self.l_a.set_data(np.arange(min(50, i + 1)), self.a_data[max(0, i - 49): i + 1])
            self.l_d.set_data(np.arange(min(50, i + 1)), self.d_data[max(0, i - 49): i + 1])
            self.rect.set_xy(self.rect_xy_buffer[i])
            self.rect.set_transform(self.rect_trans_buffer[i] + self.ax_xy.transData)
            # self.ax_v.relim()
            # self.ax_v.autoscale_view()
            # self.ax_a.relim()
            # self.ax_a.autoscale_view()
            # self.ax_d.relim()
            # self.ax_d.autoscale_view()
            artists = [self.l_v, self.l_a, self.l_d, self.rect]
            if has_prediction:
                self.l_pred.set_data(self.l_pred_buffer[i][0], self.l_pred_buffer[i][1])
                self.l_pa.set_data(self.l_pa_buffer[i][0], self.l_pa_buffer[i][1])
                self.l_pd.set_data(self.l_pd_buffer[i][0], self.l_pd_buffer[i][1])
                artists.extend((self.l_pred, self.l_pa, self.l_pd))
            if has_ss:
                self.l_ss.set_data(self.l_ss_buffer[i][0], self.l_ss_buffer[i][1])
                artists.append(self.l_ss)
            return tuple(artists)

        animation = FuncAnimation(fig=self.fig, func=update, frames=len(self.v_data), init_func=init, blit=True,
                                  interval=50)
        # plt.show()
        return animation
        # return HTML(animation.to_html5_video())

    def reset(self):
        if not self.enabled:
            self.enabled = True
            self.initialize()
        else:
            self.get_animation()
        self.l_pred_buffer = []
        self.l_ss_buffer = []
        self.l_pa_buffer = []
        self.l_pd_buffer = []
        self.l_v_buffer = []
        self.l_a_buffer = []
        self.l_d_buffer = []
        self.rect_xy_buffer = []
        self.rect_trans_buffer = []
        self.v_data_buffer = []
        self.a_data_buffer = []
        self.d_data_buffer = []

        self.v_data.clear()
        self.a_data.clear()
        self.d_data.clear()

    def close(self):
        if not self.enabled:
            return
        else:
            self.get_animation()
        self.enabled = False
        # plt.ioff()
        # plt.close(self.fig)
