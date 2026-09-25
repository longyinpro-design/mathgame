extends RefCounted
# 工坊音效：报时铃、合鸣、午休铃都在运行期合成 AudioStreamWAV，
# 不新增音频素材、不读 assets/ 下的 wav；采样率固定 22050、单声道 16 位。
# 钟的音色＝四个分音叠加（基频、八度、非谐的 2.76 与 5.4），越高的分音越轻、衰减越快。
const RATE = 22050
const PARTIALS = [[1.0,1.0,1.0],[2.01,0.45,1.5],[2.76,0.22,2.2],[5.40,0.10,3.2]]
# 午休曲试听的音高：2 拍、3 拍、4 拍各一个音，拍数越多音越高。
const LENGTH_NOTES = {2:659.26,3:783.99,4:987.77}

# strikes 里每一项是 [频率, 音量, 起始秒, 衰减]。
static func wav(seconds: float, strikes: Array) -> AudioStreamWAV:
	var count = int(RATE*seconds)
	var data = PackedByteArray()
	data.resize(count*2)
	for index in range(count):
		var t = float(index)/RATE
		var value = 0.0
		for strike in strikes:
			var local = t-strike[2]
			if local < 0.0: continue
			for part in PARTIALS:
				value += strike[1]*part[1]*exp(-local*strike[3]*part[2])*sin(TAU*strike[0]*part[0]*local)
		value = clampf(value*0.4,-1.0,1.0)
		var sample = int(value*32767.0)
		data[index*2] = sample & 0xFF
		data[index*2+1] = (sample >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream

# 单声：逐跳落地、保存成功这类短音。
static func strike(freq: float) -> AudioStreamWAV:
	return wav(0.7,[[freq,1.0,0.0,6.5]])

# 整圈走完的报时：低而长的一声。
static func bell() -> AudioStreamWAV:
	return wav(1.6,[[392.0,1.0,0.0,2.6]])

# 合鸣：两声一先一后叠着，像两只鸟对上拍。
static func duet() -> AudioStreamWAV:
	return wav(1.3,[[659.26,0.9,0.0,3.4],[987.77,0.8,0.16,3.4]])

# 午休铃：三击，最后一击高一点。
static func lunch() -> AudioStreamWAV:
	return wav(1.9,[[659.26,1.0,0.0,4.2],[659.26,0.9,0.46,4.2],[783.99,1.0,0.92,3.6]])

static func note(length: int) -> float:
	return LENGTH_NOTES.get(length,783.99)
