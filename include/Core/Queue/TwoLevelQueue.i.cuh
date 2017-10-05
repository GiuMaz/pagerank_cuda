/**
 * @author Federico Busato                                                  <br>
 *         Univerity of Verona, Dept. of Computer Science                   <br>
 *         federico.busato@univr.it
 * @date April, 2017
 * @version v2
 *
 * @copyright Copyright © 2017 cuStinger. All rights reserved.
 *
 * @license{<blockquote>
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice, this
 *   list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * * Neither the name of the copyright holder nor the names of its
 *   contributors may be used to endorse or promote products derived from
 *   this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 * </blockquote>}
 */
#include <Device/Definition.cuh>        //xlib::SMemPerBlock
#include <Device/PrintExt.cuh>          //cu::printArray
#include <Device/SafeCudaAPI.cuh>       //cuMemcpyToDeviceAsync

namespace custinger_alg {

template<typename T>
inline void ptr2_t<T>::swap() noexcept {
    std::swap(const_cast<T*&>(first), second);
}

//------------------------------------------------------------------------------

template<typename T>
TwoLevelQueue<T>::TwoLevelQueue(const custinger::cuStinger& custinger)
                               noexcept :
                                  custinger(custinger),
                                  _max_allocated_items(custinger.nV() * 2) {

    cuMalloc(_d_queue_ptrs.first, _max_allocated_items);
    cuMalloc(_d_queue_ptrs.second, _max_allocated_items);
    cuMalloc(_d_counters, 1);
    cuMemset0x00(_d_counters);
}

template<typename T>
TwoLevelQueue<T>::TwoLevelQueue(const TwoLevelQueue<T>& obj) noexcept :
                            custinger(obj.custinger),
                            _max_allocated_items(obj._max_allocated_items),
                            _d_queue_ptrs(obj._d_queue_ptrs),
                            _d_counters(obj._d_counters),
                            _kernel_copy(true) {
}

template<typename T>
inline TwoLevelQueue<T>::~TwoLevelQueue() noexcept {
    if (!_kernel_copy)
        cuFree(_d_queue_ptrs.first, _d_queue_ptrs.second, _d_counters);
}

template<typename T>
__host__ void TwoLevelQueue<T>::insert(const T& item) noexcept {
#if defined(__CUDA_ARCH__)
    unsigned       ballot = __activemask();
    unsigned elected_lane = xlib::__msb(ballot);
    int warp_offset;
    if (xlib::lane_id() == elected_lane)
        warp_offset = atomicAdd(&_d_counters->y, __popc(ballot));
    int offset = __popc(ballot & xlib::LaneMaskLT()) +
                 __shfl_sync(0xFFFFFFFF, warp_offset, elected_lane);
    _d_queue_ptrs.second[offset] = item;
#else
    cuMemcpyToHost(_d_counters, _h_counters);
    cuMemcpyToDevice(item, const_cast<int*>(_d_queue_ptrs.first) +
                                            _h_counters.x);
    _h_counters.x++;
    cuMemcpyToDevice(_h_counters, _d_counters);
#endif
}

template<typename T>
__host__ inline
void TwoLevelQueue<T>::insert(const T* items_array, int num_items) noexcept {
    cuMemcpyToHost(_d_counters, _h_counters);
    cuMemcpyToDevice(items_array, num_items,
                     _d_queue_ptrs.first + _h_counters.x);
    _h_counters.x += num_items;
    cuMemcpyToDevice(_h_counters, _d_counters);
}

template<typename T>
__host__ void TwoLevelQueue<T>::swap() noexcept {
    _d_queue_ptrs.swap();

    cuMemcpyToHost(_d_counters, _h_counters);
    _h_counters.x = _h_counters.y;
    _h_counters.y = 0;
    cuMemcpyToDevice(_h_counters, _d_counters);
}

template<typename T>
__host__ void TwoLevelQueue<T>::clear() noexcept {
    cuMemset0x00(_d_counters);
}

template<typename T>
__host__ const T* TwoLevelQueue<T>::device_input_ptr() const noexcept {
    return _d_queue_ptrs.first;
}

template<typename T>
__host__ const T* TwoLevelQueue<T>::device_output_ptr() const noexcept {
    return _d_queue_ptrs.second;
}
/*
template<typename T>
__host__ const T* TwoLevelQueue<T>::host_data() noexcept {
    if (_host_data == nullptr)
        _host_data = new T[_max_allocated_items];
    cuMemcpyToHost(_d_queue_ptrs.second, _num_queue_vertices, _host_data);
    return _host_data;
}*/
/*
template<typename T>
__host__ int TwoLevelQueue<T>::size() noexcept {
    cuMemcpyToHost(_d_queue_counter, _num_queue_vertices);
    return _num_queue_vertices;
}*/

template<typename T>
__host__ int TwoLevelQueue<T>::size() noexcept {
    int2 _h_counters;
    cuMemcpyToHost(_d_counters, _h_counters);
    return _h_counters.x;
}

template<typename T>
__host__ int TwoLevelQueue<T>::output_size() noexcept {
    int2 _h_counters;
    cuMemcpyToHost(_d_counters, _h_counters);
    return _h_counters.y;
}

template<typename T>
__host__ void TwoLevelQueue<T>::print_input() noexcept {
    int2 _h_counters;
    cuMemcpyToHost(_d_counters, _h_counters);
    cu::printArray(_d_queue_ptrs.first, _h_counters.x);
}

template<typename T>
__host__ void TwoLevelQueue<T>::print_output() noexcept {
    int2 _h_counters;
    cuMemcpyToHost(_d_counters, _h_counters);
    cu::printArray(_d_queue_ptrs.second, _h_counters.y);
}

} // namespace custinger_alg
