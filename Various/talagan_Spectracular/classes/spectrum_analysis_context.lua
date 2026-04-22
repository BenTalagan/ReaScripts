-- @noindex
-- @author Ben 'Talagan' Babut
-- @license MIT
-- @description This file is part of Spectracular

local MIDI      = require "modules/midi"
local DSP       = require "modules/dsp"
local LOG       = require "modules/log"
local S         = require "modules/settings"
local RENDER    = require "modules/render"
local CSV       = require "modules/csv"

local Spectrogram    = require "classes/spectrogram"
local SampleAccessor = require "classes/sample_accessor"

-- Main analysing code

---------------------------------

--[[
local octava_settings = {
[-1] = { full_width = 16384 , eff_width = 16384},
[0]  = { full_width =  8192 , eff_width =  8192},
[1]  = { full_width =  8192 , eff_width =  8192},
[2]  = { full_width =  8192 , eff_width =  8192},
[3]  = { full_width =  8192 , eff_width =  8192},
[4]  = { full_width =  8192 , eff_width =  8192},
[5]  = { full_width =  8192 , eff_width =  8192},
[6]  = { full_width =  8192 , eff_width =  8192},
[7]  = { full_width =  8192 , eff_width =  8192},
[8]  = { full_width =  8192 , eff_width =  8192},
}
]]

local UI_REFRESH_INTERVAL_SECONDS = 0.05

---------------------------------

local SpectrumAnalysisContext = {}
SpectrumAnalysisContext.__index = SpectrumAnalysisContext

-- sample_rate is the sample rate of the signal to anayse
function SpectrumAnalysisContext:new(params)
    local instance = {}
    setmetatable(instance, self)
    instance:_initialize(params)
    return instance
end

function SpectrumAnalysisContext:_initialize(params)
    self.params = params
end

function SpectrumAnalysisContext:_buildAndRender()
    local params = self.params

    -- First, perform the right rendering
    local source_ctx = RENDER.render({
        channel_mode        = S.instance_params.channel_mode,
        ts                  = self.params.ts,
        te                  = self.params.te,
        time_resolution_ms  = self.params.time_resolution_ms,
        tracks              = self.params.tracks
    })

    if not source_ctx.success then
        self.error              = source_ctx.err
        self.analysis_finished  = true
        return
    end

    self.signal                 = source_ctx
    self.tracks                 = source_ctx.tracks
    self.sample_rate            = source_ctx.sample_rate
    self.chan_count             = source_ctx.chan_count

    self.fft_size               = params.fft_size

    self.slice_step             = math.floor((params.time_resolution_ms / 1000.0) * source_ctx.sample_rate)
    self.slice_step_duration    = 1.0 * self.slice_step / self.sample_rate

    self.low_octava             = params.low_octava
    self.high_octava            = params.high_octava

    self.low_note               = MIDI.noteNumber(self.low_octava  - 1, 11)
    self.high_note              = MIDI.noteNumber(self.high_octava + 1,  0)

    -- Build buffers for each octava
    self.fft_params             = self:_buildFFTParamsAndBuffers()

    -- Count the number of slices we will have, and adjust the sample count so that last slice falls on an full count of samples
    self:_countSlices()
    -- Build buffers for slice analysis : energy per quarter of note
    self:_calcSliceSizeAndBuildNoteBuffers()
    -- Build result data buffers
    self:_buildSpectrogramBuffers()

    -- Initialize reassignment rolling buffers
    if self.params.reassignment then
        self:_reinitReassignmentBuffers()
    end

    self.sample_accessor        = SampleAccessor:new(self)
end


function SpectrumAnalysisContext:_countSlices()
    local signal        = self.signal

    self.frame_count    = self.signal.frame_count

    -- We're going to trim the signal so that the number of samples is a multiple of slice_step
    -- (Remove extra samples at the end)
    local kept_slices  = math.floor(self.frame_count / self.slice_step)
    if kept_slices == 0 then
        self.signal_too_short = true
        error("Signal is too short : todo handle this case a better way")
        return
    end

    -- Recalculate the sample count
    self.slice_count    = kept_slices
    self.frame_count    = self.slice_count * self.slice_step

    -- Update the signal end time after triming
    signal.stop         = signal.start + (self.frame_count / signal.sample_rate)
end

function SpectrumAnalysisContext:_buildFFTParamsAndBuffers()

    local samplerate                        = self.sample_rate * 1.0
    local sample_count                      = self.fft_size
    local zero_padding_sample_count         = math.floor(self.fft_size * self.params.zero_padding_percent / 100.0)
    local effective_window_sample_count     = sample_count - zero_padding_sample_count

    -- Number of bins in the FFT. Remember we're using fft_real so we need to divide by 2
    local bin_count         = sample_count/2
    -- Bandwidth of an FFT bin
    local bin_fwidth        = samplerate / sample_count

    -- Pre-allocate working buffers
    local sample_buf            = reaper.new_array(sample_count)

    local x1_buf                = reaper.new_array(sample_count)
    local x2_buf                = reaper.new_array(sample_count) -- used for reassignment
    local x3_buf                = reaper.new_array(sample_count) -- used for reassignment

    local fft_bin_buf           = reaper.new_array(bin_count)
    local bin_freq_buf          = reaper.new_array(bin_count)

    -- Fill the bin freqs with the corresponding frequencies
    DSP.array_fill_bin_freqs(bin_freq_buf, bin_fwidth)

    return {
        sample_buf                      = sample_buf,

        x1_buf                          = x1_buf,
        x2_buf                          = x2_buf,
        x3_buf                          = x3_buf,

        -- Buffer for all bin energies
        fft_bin_buf                     = fft_bin_buf,
        -- Buffer for all central frequencies of bins
        bin_freq_buf                    = bin_freq_buf,
        -- Number of bins, and frequency width of a bin
        bin_count                       = bin_count,
        bin_fwidth                      = bin_fwidth,

        -- Parameters for keeping or throwing bins away when building the final curve
        full_window_sample_count        = sample_count,
        full_window_duration            = sample_count / samplerate,

        effective_window_sample_count   = effective_window_sample_count,
        effective_window_duration       = effective_window_sample_count / samplerate,

         -- indication for the zero-padding
        padding_size                    = sample_count - effective_window_sample_count,
    }
end

-- Buffers to process FFT results
function SpectrumAnalysisContext:_calcSliceSizeAndBuildNoteBuffers()
    local range = self:noteRange()

    -- Use 5 frequencies per semitone
    self.semi_tone_slices = 5

    -- Add 1 to complete the loop, because we want to convert this into a BMP
    -- And we want a boudnary on the first and last pixels vertically
    local number_of_wanted_frequencies = (range.note_count - 1) * self.semi_tone_slices + 1

    self.note_freq_buf          = reaper.new_array(number_of_wanted_frequencies)
    self.note_freq_energy_buf   = reaper.new_array(number_of_wanted_frequencies)

    local note_interval = 1.0/self.semi_tone_slices
    local note_num      = self.low_note
    local ni            = 0

    while ni < number_of_wanted_frequencies do
        self.note_freq_buf[ni+1]    = MIDI.noteToFrequency(note_num)
        ni                          = ni + 1
        note_num                    = note_num + note_interval -- Quarter of tones
    end

    self.slice_size = #self.note_freq_buf
end

function SpectrumAnalysisContext:_buildSpectrogramBuffers()
    self.spectrograms = {}
    self.rmse         = {}

    for ci=1, self.chan_count do
        self.spectrograms[ci] = Spectrogram:new(self, ci)
        self.rmse[ci]         = reaper.new_array(self.slice_count)
    end
end

function SpectrumAnalysisContext:_reinitReassignmentBuffers()

    -- TODO : may use something something dynamic
    self.reassign_roll_window          = 33
    self.reassign_roll_half_window     = math.floor(self.reassign_roll_window * 0.5)

    DSP.fft_reassign_rolling_init(self.chan_count, self.reassign_roll_window, self.fft_params.bin_count, self.fft_params.bin_fwidth, self.sample_rate, self.slice_step_duration, self.fft_params.full_window_sample_count, self.fft_params.effective_window_sample_count )

    -- Scalar rings for per-slice normalisation params (size W, indexed by si % W)
    self.reassign_ring_applied_window = {}
    self.reassign_ring_max_energy     = {}

    for i = 1, self.reassign_roll_window do
        self.reassign_ring_applied_window[i] = 1
        self.reassign_ring_max_energy[i]     = 1
    end
end

function SpectrumAnalysisContext:resumeAnalysis()

    self.analysis_chunk_start = reaper.time_precise()

    -- This may be resumed, so remember that progress.si may not be at 0 when entering the function
    while self.progress.si < self.slice_count do

        -- Get the center of our slice : add one semi-slice
        -- The frame offset is the index of the first sample of the window / slices we're going to analyse
        local frame_offset = math.floor( (0.5 + self.progress.si) * self.slice_step )
        local ring_head    = 0

        if self.params.reassignment then
            -- We use a rolling buffer with rolling width slots
            -- The head is the current data push / analysis slot
            ring_head = self.progress.si % self.reassign_roll_window
        end

        for ci=1, self.chan_count do

            if self.params.reassignment then
                -- Reassignment pipeline
                -- Step 1 : main FFT
                self:_prepareAndPerformFFT(ci, frame_offset, true)
                -- Normalize the result

                -- Store per-slice normalisation params in scalar rings; beware of lua indices
                self.reassign_ring_applied_window[ring_head+1] = self.fft_params.applied_window_sample_count
                self.reassign_ring_max_energy[ring_head+1]     = self.fft_params.max_energy

                -- Feed the function with FFT results
                DSP.fft_reassign_feed_x1_fft(self.fft_params.x1_buf)
                DSP.fft_reassign_feed_x2_fft(self.fft_params.x2_buf)
                DSP.fft_reassign_feed_x3_fft(self.fft_params.x3_buf)

                -- Feed the function with FFT bins
                DSP.fft_reassign_feed_base_mag(self.fft_params.fft_bin_buf)

                -- Step 3 : Now, FFT, shifted FFT and main BINs are all pushed into the temp buffers
                -- Apply reassignment into accumulation buffers
                DSP.fft_reassign_process_current_for_chan(ci-1, self.fft_params.max_energy) -- Beware lua index !

            else
                -- Normal pipeline
                self:_prepareAndPerformFFT(ci, frame_offset, true)
                -- Normalize the result
                self:_normalizeFFT()
                -- Interpolate for notes instead of frequencies
                DSP.resample_curve(self.fft_params.bin_freq_buf, self.fft_params.fft_bin_buf, self.note_freq_buf, self.note_freq_energy_buf, false, "akima")
                -- Copy into slices the content of the new energies for this slice, at the offset of the slice
                self.spectrograms[ci]:saveSlice(self.note_freq_energy_buf, self.progress.si)
            end

            -- RMSE (uses its own sample window, independent of FFT)
            self.rmse[ci][self.progress.si + 1] = self:_performRMSE(ci, frame_offset)
        end

        if self.params.reassignment then
            local outed_slice = self.progress.si - self.reassign_roll_half_window
            if outed_slice >= 0 then
                local ring_trail = ring_head - self.reassign_roll_half_window
                if (ring_trail < 0) then ring_trail = ring_trail + self.reassign_roll_window end

                for ci=1, self.chan_count do
                    self:_bakeReassignedSlice(ci-1, outed_slice, ring_trail)
                end
            end

            -- Now advance and zero outed slice
            DSP.fft_reassign_advance()
        end

        self.progress.si = self.progress.si + 1

        if (reaper.time_precise() - self.analysis_chunk_start) > UI_REFRESH_INTERVAL_SECONDS then
            -- Interrupt the calculation to let reaper do other stuff
            return false
        end
    end

    -- Flush phase : drain remaining HALF_W slices from rolling buffer
    if self.params.reassignment then
        local flushi = 0
        while flushi < self.reassign_roll_half_window do
            local slice_i       = self.slice_count + flushi -- This is beyond the last slice but it's ok
            local ring_head     = slice_i % self.reassign_roll_window
            local outed_slice   = slice_i - self.reassign_roll_half_window
            local ring_trail    = ring_head - self.reassign_roll_half_window
            if (ring_trail < 0) then ring_trail = ring_trail + self.reassign_roll_window end

            for ci=1, self.chan_count do
                self:_bakeReassignedSlice(ci-1, outed_slice, ring_trail)
            end

            flushi = flushi + 1
        end
    end

    -- Destroy the audio accessor open on the rendered file
    reaper.DestroyAudioAccessor(self.signal.audio_accessor)
    -- Destroy the audio file
    os.remove(self.signal.file_name)
    -- Mark as finished
    self.analysis_finished = true

    LOG.debug("---\n")
    LOG.debug("Energy conservation successfull tests : " .. self.energy_conservation_test_success .. " / " .. self.energy_conservation_test_count .. "\n")
    LOG.debug("---\n")
end



-- Convert committed bin magnitudes to dB, resample to note grid, and save into spectrograms.
-- applied_window and max_energy are the per-slice normalisation params stored in the scalar rings.
-- All indices are 0 based.
function SpectrumAnalysisContext:_bakeReassignedSlice(chan, outed_slice, outed_ring_index)
    local fft_params = self.fft_params

    -- Beware of lua indices for the ring buffers
    local full_norm  = self:_computeNormalizationFactor(fft_params.full_window_sample_count,
    self.reassign_ring_applied_window[outed_ring_index+1],
    self.reassign_ring_max_energy[outed_ring_index+1])

    -- Read the data from the reassign function memory, use fft_param.fft_bin_buf which is available
    DSP.fft_reassign_read_ring_slice_for_chan(chan, outed_ring_index, fft_params.fft_bin_buf)

    -- fft_bin_buf holds the committed reassigned magnitudes (output of rolling push/flush)
    DSP.fft_bins_to_db(fft_params.fft_bin_buf, full_norm, -90)
    DSP.resample_curve(fft_params.bin_freq_buf, fft_params.fft_bin_buf, self.note_freq_buf, self.note_freq_energy_buf, false, "akima")

    self.spectrograms[chan+1]:saveSlice(self.note_freq_energy_buf, outed_slice)
end


function SpectrumAnalysisContext:analyze()
    if not self.progress then
        -- First call to analyse
        -- Initialize state vars so that we can pause/resume the analysis
        self.analysis_finished     = false

        self.energy_conservation_test_count   = 0
        self.energy_conservation_test_success = 0

        self.progress    = {}
        self.progress.si = 0

        self:_buildAndRender()

        self.render_finished = true
    end

    if self.analysis_finished then return end

    self:resumeAnalysis()
end


function SpectrumAnalysisContext:getProgress()
    local prog = 0.1

    if not self.render_finished then return prog, math.floor(prog * 100) .. " % - Rendering..." end
    if self.analysis_finished   then return 1,    "100 % - Finished" end

    prog = prog + (1-prog) * self.progress.si / ( 1.0 * self.slice_count)

    return prog, math.floor(prog * 100) .. " % - Processing..."
end


function SpectrumAnalysisContext:noteRange()
    return {
        low_octava      = self.low_octava,
        high_octava     = self.high_octava,

        low_note        = self.low_note,
        high_note       = self.high_note,

        note_count      = self.high_note - self.low_note + 1,
        octava_count    = self.high_octava - self.low_octava + 1,
    }
end

function SpectrumAnalysisContext:_performRMSE(chan_num, offset_center)
    local win = self.params.rms_window -- ???
    local left_src_sample = math.floor(offset_center - 0.5 * win)
    -- Make sure we're ok on the left
    if left_src_sample < 0 then left_src_sample = 0 end
    local right_src_sample = math.floor(offset_center + 0.5 * win)
    -- Make sure we're ok on the right
    if right_src_sample > self.frame_count - 1 then right_src_sample = self.frame_count - 1 end
    -- Number of samples kept due to potential border problems
    local win_sample_count = right_src_sample - left_src_sample

    local src_offset = left_src_sample

    -- The array size may change on boundaries but it's not a big deal
    self.rmse_buf = DSP.ensure_array_size(self.rmse_buf, win_sample_count)

    -- Get the samples into our temporary buffer
    self.sample_accessor:getSamples(src_offset, win_sample_count, chan_num, self.rmse_buf, 0)

    return DSP.rmse(self.rmse_buf)
end

-- After this call, fft_params.x1_buf contains the complex FFT (re,im interleaved)
-- and fft_params.fft_bin_buf contains the magnitude bins.
function SpectrumAnalysisContext:_prepareAndPerformFFT(chan_num, offset_center, want_energy)
    local fft_params = self.fft_params

    -- Clear the buffer so that it's zeroed.
    -- The sample buf is of the size of the FFT, but there may be left samples inside
    -- If we're on the borders, or if we apply zero padding
    fft_params.sample_buf.clear()

    local win             = fft_params.effective_window_sample_count -- affected by zero padding
    local left_src_sample = math.floor(offset_center - 0.5 * win)

    -- Make sure we're ok on the left
    if left_src_sample < 0 then left_src_sample = 0 end

    local right_src_sample = math.floor(offset_center + 0.5 * win)

    -- Make sure we're ok on the right
    if right_src_sample > self.frame_count - 1 then right_src_sample = self.frame_count - 1 end

    -- Number of samples kept due to potential border problems
    local win_sample_count = right_src_sample - left_src_sample
    local dst_offset       = math.floor(0.5 * (fft_params.full_window_sample_count - win_sample_count))
    local src_offset       = left_src_sample

    if dst_offset < 0 then
        error("Wrong use of the FFT !! Trying to get samples before the start of the sample serie.")
    end

    -- Get the samples into our temporary buffer
    self.sample_accessor:getSamples(src_offset, win_sample_count, chan_num, fft_params.sample_buf, dst_offset)

    -- Apply the windowing. Use the real number of samples in the buffer as window size.
    -- The rest is zero pad, either asked by the user (zero padding), or due to border adjustment.
    local apply_windowing = true
    local sig_energy, max_energy
    if apply_windowing then
        sig_energy, max_energy = DSP.window_hann(fft_params.sample_buf, dst_offset + 1, win_sample_count, self.params.reassignment, fft_params.x1_buf, fft_params.x2_buf, fft_params.x3_buf)
    else
        sig_energy, max_energy = DSP.window_rect(fft_params.sample_buf, dst_offset + 1, win_sample_count, self.params.reassignment, fft_params.x1_buf, fft_params.x2_buf, fft_params.x3_buf)
    end

    fft_params.applied_window_sample_count = win_sample_count
    fft_params.sig_energy                  = sig_energy
    fft_params.max_energy                  = max_energy

    -- FFT in-place : contains complex spectrum (re,im interleaved)
    fft_params.x1_buf.fft_real(#fft_params.x1_buf, true)

    if self.params.reassignment then
        -- We also need the FFTs of x2 and x3 for reassignements
        fft_params.x2_buf.fft_real(#fft_params.x2_buf, true)
        fft_params.x3_buf.fft_real(#fft_params.x3_buf, true)
    end

    if want_energy then
        -- Compute magnitude bins
        local fft_energy = DSP.fft_to_fft_bins(fft_params.x1_buf, fft_params.fft_bin_buf)

        -- Energy conservation check (main window only)
        self.energy_conservation_test_count = self.energy_conservation_test_count + 1
        if math.abs(fft_energy - sig_energy) / fft_energy > 0.05 then
            LOG.debug("Energy not conserved !! : FFT E vs BUF E : " .. fft_energy .. " / " .. sig_energy .. " (FFT Size : " .. fft_params.full_window_sample_count .. ")\n")
        else
            self.energy_conservation_test_success = self.energy_conservation_test_success + 1
        end
        fft_params.fft_energy = fft_energy
    end
end

-- Computes the normalisation factor to be applied to the result of the FFT
-- For bin magnitude to DB correction.
-- Multiple factors are affecting the result that may vary accross the analysis
--    -- Full window size : if we use more samples, there's more global energy in our global window, so we need to normalize things back
--    -- Applied window size : Zero padding changes the size of the applied window and thus when we zero pad, less samples are used so the energy of the full window is lower and overall should be normalized
--    -- Max energy : when we apply complex windows like Hann, we remove some global energy from the initial window. Max energy is the maximum energy that can be stored in that window.
--
-- fft_size                         : size of the window / total number of samples in time window
-- applied_window_sample_count      : number of effective samples in time window (zero-padding /boundaries applied)
-- max_energy                       : max possible energy after window is applied (all samples at 1)
--
--
--              <--- applied -->
--                 _________
-- |           |__/         \__|          |
-- |                                      |
-- |<------------ Full window ----------->|
--

function SpectrumAnalysisContext:_computeNormalizationFactor(full_window_size, applied_window_size, max_energy)
   -- Normalize the results by applying various corrections.
    local db_correction_6         = 0.25
    -- Size of the fft window
    local standard_normalisation  = full_window_size
    -- Number of samples really used / fft size proportion (zero pad)
    local zero_pad_normalisation  = applied_window_size / full_window_size
    -- Windowing factor : when using a window the signal is modified, and thus the energy. Apply inverse correction.
    local windowing_normalisation = max_energy / applied_window_size

    zero_pad_normalisation        = zero_pad_normalisation * zero_pad_normalisation

    local full_normalisation      = db_correction_6 * zero_pad_normalisation * standard_normalisation * windowing_normalisation

    return full_normalisation
end

function SpectrumAnalysisContext:_normalizeFFT()
    -- Convert FFT bins to decibels and apply normalization

    local fft_params = self.fft_params

    local full_normalisation = self:_computeNormalizationFactor(fft_params.full_window_sample_count, fft_params.applied_window_sample_count, fft_params.max_energy)

    DSP.fft_bins_to_db(fft_params.fft_bin_buf, full_normalisation, -90)
end


function SpectrumAnalysisContext:fftHalfWindowDurationForOctava(octava)
    local samples = self.fft_params.effective_window_sample_count * 0.5
    return samples / self.sample_rate
end

-- Data index accessor for note_num
function SpectrumAnalysisContext:profileNumForNoteNum(note_num)
    if note_num < self.low_note   then note_num = self.low_note  end
    if note_num > self.high_note  then note_num = self.high_note end

    local note_offset = (note_num - self.low_note) / (self.high_note - self.low_note)

    return math.floor( 0.5 + note_offset * (#self.note_freq_buf-1) )
end

-- Data index accessor for time
function SpectrumAnalysisContext:sliceNumForTime(time)
    if time < self.signal.start then time = self.signal.start end
    if time > self.signal.stop  then time = self.signal.stop end

    return math.floor(0.5 + (self.slice_count - 1) * (time - self.signal.start) / (self.signal.stop - self.signal.start))
end

function SpectrumAnalysisContext:sampleNumForTime(time)
    if time < self.signal.start then time = self.signal.start end
    if time > self.signal.stop  then time = self.signal.stop end

    return math.floor(0.5 + self.signal.sample_rate * (time - self.signal.start))
end

function SpectrumAnalysisContext:extractNoteProfile(chan_num, note_num, profile_buf)
    if not profile_buf then error("Developer error : should pass a valid reaper_array") end

    profile_buf = DSP.ensure_array_size(profile_buf, self.slice_count)
    local profile_num = self:profileNumForNoteNum(note_num)
    self.spectrograms[chan_num]:extractNoteProfile(profile_buf, profile_num)
end

function SpectrumAnalysisContext:extractSliceProfile(chan_num, time, profile_buf)
    if not profile_buf then error("Developer error : should pass a valid reaper_array") end

    profile_buf = DSP.ensure_array_size(profile_buf, self.slice_size)
    local slice_num = self:sliceNumForTime(time)
    self.spectrograms[chan_num]:extractSlice(profile_buf, slice_num)
end

function SpectrumAnalysisContext:extractRmseProfile(chan_num, profile_buf)
    local rmse = self.rmse[chan_num]

    if not profile_buf then error("Developer error : should pass a valid reaper_array") end
    profile_buf = DSP.ensure_array_size(profile_buf, #rmse)
    profile_buf.copy(rmse)
end

function SpectrumAnalysisContext:getRmseValueAt(chan_num, time)
    local slice_num = self:sliceNumForTime(time)

    return self.rmse[chan_num][slice_num+1]
end

function SpectrumAnalysisContext:getValueAt(chan_num, note_num, time)
    local slice_num   = self:sliceNumForTime(time)
    local profile_num = self:profileNumForNoteNum(note_num)

    return self.spectrograms[chan_num]:getValueForSliceAndProfile(slice_num, profile_num)
end

return SpectrumAnalysisContext
