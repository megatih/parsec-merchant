// SPDX-License-Identifier: GPL-2.0-or-later
// Headless driver for the C# 2.01 game logic. Emits JSON fixtures consumed by the Swift tests (PRD §8.4).
// Usage: ParsecHarness <command> <outDir>
//   rng     — System.Random vectors (seeded)
//   galaxy  — universe/crew/commander/prices for several seeds and difficulties
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace Fryz.Apps.SpaceTrader
{
	public static class HarnessDriver
	{
		static readonly JsonSerializerOptions Json = new JsonSerializerOptions { WriteIndented = false };

		public static int Main(string[] args)
		{
			if (args.Length < 2) { Console.Error.WriteLine("usage: ParsecHarness <rng|galaxy|all> <outDir>"); return 2; }
			string cmd = args[0], dir = args[1];
			Directory.CreateDirectory(dir);
			if (cmd == "rng" || cmd == "all") Write(dir, "rng-dotnet.json", Rng());
			if (cmd == "galaxy" || cmd == "all") Write(dir, "galaxy-windows201.json", Galaxies());
			if (cmd == "market" || cmd == "all") Write(dir, "market-windows201.json", MarketSteps());
			if (cmd == "opponents" || cmd == "all") Write(dir, "opponents-windows201.json", Opponents());
			if (cmd == "combat" || cmd == "all") Write(dir, "combat-windows201.json", Combat());
			if (cmd == "travel" || cmd == "all") Write(dir, "travel-windows201.json", Travel());
			return 0;
		}

		static void Write(string dir, string name, object o)
		{
			File.WriteAllText(Path.Combine(dir, name), JsonSerializer.Serialize(o, Json) + "\n");
			Console.WriteLine("wrote " + name);
		}

		public static void SeedRandom(int seed)
		{
			FieldInfo f = typeof(Functions).GetField("rand", BindingFlags.NonPublic | BindingFlags.Static);
			f.SetValue(null, new Random(seed));
		}

		static object Rng()
		{
			var list = new List<object>();
			foreach (int seed in new[] { 0, 1, 42, 12345, 2147483647, -2147483648, -42 })
			{
				var r1 = new Random(seed); var next = new List<int>(); for (int i = 0; i < 20; i++) next.Add(r1.Next());
				var r2 = new Random(seed); var below = new List<int>(); foreach (int m in new[] { 1, 2, 5, 6, 10, 17, 100, 1000, 0, 154, 110, 13 }) below.Add(r2.Next(0, m));
				var r3 = new Random(seed); var range = new List<int>(); foreach (var p in new[] { (-12, 13), (1, 8), (1, 13), (5, 5), (-4, 5), (9, 14) }) range.Add(r3.Next(p.Item1, p.Item2));
				var r4 = new Random(seed); var doubles = new List<double>(); for (int i = 0; i < 5; i++) doubles.Add(r4.NextDouble());
				list.Add(new { seed, next, belowMax = new[] { 1, 2, 5, 6, 10, 17, 100, 1000, 0, 154, 110, 13 }, below, rangePairs = new[] { "-12,13", "1,8", "1,13", "5,5", "-4,5", "9,14" }, range, doubles });
			}
			return list;
		}

		static object Galaxies()
		{
			var list = new List<object>();
			foreach (int seed in new[] { 0, 1, 2, 3, 42, 1000, 12345 })
				foreach (Difficulty d in new[] { Difficulty.Beginner, Difficulty.Normal, Difficulty.Impossible })
					list.Add(GalaxySnapshot(seed, d));
			return list;
		}

		public static object GalaxySnapshot(int seed, Difficulty d)
		{
			SeedRandom(seed);
			var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
			var systems = new List<object>();
			foreach (StarSystem s in game.Universe)
			{
				var qty = new int[10];
				for (int i = 0; i < 10; i++) qty[i] = s.TradeItems[i];
				systems.Add(new
				{
					id = (int)s.Id, x = s.X, y = s.Y, size = (int)s.Size, tech = (int)s.TechLevel, politics = (int)s.PoliticalSystemType,
					pressure = (int)s.SystemPressure, resource = (int)SpecialResourceRaw(s), special = (int)s.SpecialEventType,
					shipyard = (int)s.ShipyardId, quantities = qty, countdown = s.CountDown, visited = s.Visited
				});
			}
			var crew = new List<object>();
			foreach (CrewMember c in game.Mercenaries)
				crew.Add(new { id = (int)c.Id, skills = c.Skills, system = c.CurrentSystemId == StarSystemId.NA ? -1 : (int)c.CurrentSystemId });
			var cmdr = game.Commander;
			return new
			{
				seed, difficulty = (int)d, wormholes = game.Wormholes, systems, crew,
				commander = new { system = (int)cmdr.CurrentSystemId, cash = cmdr.Cash, ship = (int)cmdr.Ship.Type, fuel = cmdr.Ship.Fuel, hull = cmdr.Ship.Hull },
				buyPrices = game.PriceCargoBuy, sellPrices = game.PriceCargoSell
			};
		}

		/// Restock/pressure/price evolution: after construction, set countdowns, mark some systems visited,
		/// choose a warp system and run ArrivalUpdatePressuresAndQuantities + CalculatePrices(warp) several times.
		static object MarketSteps()
		{
			var list = new List<object>();
			MethodInfo arrive = typeof(Game).GetMethod("ArrivalUpdatePressuresAndQuantities", BindingFlags.NonPublic | BindingFlags.Instance);
			MethodInfo calc = typeof(Game).GetMethod("CalculatePrices", BindingFlags.NonPublic | BindingFlags.Instance);
			foreach (int seed in new[] { 7, 42 })
			{
				foreach (Difficulty d in new[] { Difficulty.Easy, Difficulty.Hard })
				{
					SeedRandom(seed);
					var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
					var steps = new List<object>();
					for (int step = 0; step < 6; step++)
					{
						int warp = (step * 37 + seed) % game.Universe.Length;
						for (int i = 0; i < game.Universe.Length; i += 3) game.Universe[i].CountDown = (i + step) % 7;
						for (int i = 0; i < game.Universe.Length; i += 5) game.Universe[i].Visited = true;
						game.Commander.PoliceRecordScore = step % 2 == 0 ? 0 : -10;
						typeof(Game).GetField("_warpSystemId", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(game, (StarSystemId)warp);
						arrive.Invoke(game, null);
						calc.Invoke(game, new object[] { game.Universe[warp] });
						var qty = new List<int[]>(); var press = new List<int>(); var cd = new List<int>();
						foreach (StarSystem sys in game.Universe)
						{
							var q = new int[10]; for (int i = 0; i < 10; i++) q[i] = sys.TradeItems[i];
							qty.Add(q); press.Add((int)sys.SystemPressure); cd.Add(sys.CountDown);
						}
						steps.Add(new { warp, record = game.Commander.PoliceRecordScore, quantities = qty, pressures = press, countdowns = cd,
							buyPrices = (int[])game.PriceCargoBuy.Clone(), sellPrices = (int[])game.PriceCargoSell.Clone() });
					}
					list.Add(new { seed, difficulty = (int)d, steps });
				}
			}
			return list;
		}

		static object ShipDump(Ship sh)
		{
			var w = new List<int>(); foreach (Weapon x in sh.Weapons) w.Add(x == null ? -1 : (int)x.Type);
			var sl = new List<int>(); var sc = new List<int>(); foreach (Shield x in sh.Shields) { sl.Add(x == null ? -1 : (int)x.Type); sc.Add(x == null ? 0 : x.Charge); }
			var g = new List<int>(); foreach (Gadget x in sh.Gadgets) g.Add(x == null ? -1 : (int)x.Type);
			var crew = new List<object>(); foreach (CrewMember c in sh.Crew) crew.Add(c == null ? null : (object)new { id = (int)c.Id, skills = (int[])c.Skills.Clone() });
			return new { type = (int)sh.Type, hull = sh.Hull, fuel = sh.Fuel, weapons = w, shields = sl, charges = sc, gadgets = g, cargo = (int[])sh.Cargo.Clone(), crew };
		}

		/// Opponent generation: for several games, warp targets, records and worth levels, generate opponents in sequence.
		static object Opponents()
		{
			var list = new List<object>();
			foreach (int seed in new[] { 3, 42 })
			{
				foreach (Difficulty d in new[] { Difficulty.Beginner, Difficulty.Normal, Difficulty.Impossible })
				{
					SeedRandom(seed);
					var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
					var cases = new List<object>();
					int n = 0;
					foreach (int cash in new[] { 1000, 400000, 2000000 })
					{
						foreach (int record in new[] { 10, -10, -80, -150 })
						{
							foreach (OpponentType t in new[] { OpponentType.Pirate, OpponentType.Police, OpponentType.Trader, OpponentType.Mantis, OpponentType.FamousCaptain, OpponentType.Bottle })
							{
								int warp = (n * 29 + seed) % game.Universe.Length; n++;
								typeof(Game).GetField("_warpSystemId", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(game, (StarSystemId)warp);
								game.Commander.Cash = cash;
								game.Commander.PoliceRecordScore = record;
								var opp = new Ship(t);
								cases.Add(new { warp, cash, record, oppType = (int)t, ship = ShipDump(opp) });
							}
						}
					}
					list.Add(new { seed, difficulty = (int)d, cases });
				}
			}
			return list;
		}

		/// Combat: generate an opponent, set an encounter type, and run EncounterExecuteAction until it ends
		/// (or 25 rounds), recording ships and state after each round. Dialogs answer "No" (scoop declined).
		static object Combat()
		{
			Harness.Policy = _ => DialogResult.No;
			var list = new List<object>();
			foreach (int seed in new[] { 5, 11, 42 })
			{
				foreach (Difficulty d in new[] { Difficulty.Beginner, Difficulty.Normal, Difficulty.Impossible })
				{
					SeedRandom(seed);
					var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
					var fights = new List<object>();
					var setups = new[] {
						(OpponentType.Pirate, EncounterType.PirateAttack, false, 0),
						(OpponentType.Police, EncounterType.PoliceAttack, false, 1),
						(OpponentType.Trader, EncounterType.TraderAttack, false, 2),
						(OpponentType.Pirate, EncounterType.PirateAttack, true, 3),
						(OpponentType.Trader, EncounterType.TraderIgnore, false, 4),
						(OpponentType.Pirate, EncounterType.PirateAttack, false, 5) };
					int n = 0;
					foreach (var (ot, et, flee, variant) in setups)
					{
						for (int rep = 0; rep < 3; rep++)
						{
							int warp = (n * 31 + seed) % game.Universe.Length; n++;
							typeof(Game).GetField("_warpSystemId", BindingFlags.NonPublic | BindingFlags.Instance).SetValue(game, (StarSystemId)warp);
							// Fresh well-armed commander ship each fight.
							var ship = new Ship(variant >= 3 ? ShipType.Wasp : ShipType.Hornet);
							ship.Crew[0] = game.Commander;
							for (int i = 0; i < ship.Weapons.Length; i++) ship.AddEquipment(Consts.Weapons[variant == 5 ? (int)WeaponType.PhotonDisruptor : (int)WeaponType.BeamLaser]);
							for (int i = 0; i < ship.Shields.Length; i++) ship.AddEquipment(Consts.Shields[(int)ShieldType.Energy]);
							game.Commander.Ship = ship;
							game.Commander.Cash = 5000; game.Commander.PoliceRecordScore = 0;
							game.Options.DisableOpponents = variant == 5;
							game.Options.ContinuousAttack = variant == 2;
							game.Opponent = new Ship(ot);
							game.EncounterType = et;
							game.OpponentDisabled = false;
							game.EncounterCmdrFleeing = flee;
							var start = new { cmdr = ShipDump(game.Commander.Ship), opp = ShipDump(game.Opponent) };
							var rounds = new List<object>();
							for (int round = 0; round < 25; round++)
							{
								var result = game.EncounterExecuteAction(null);
								rounds.Add(new { result = (int)result, type = (int)game.EncounterType, disabled = game.OpponentDisabled,
									cmdrHull = game.Commander.Ship.Hull, cmdrCharges = Charges(game.Commander.Ship), oppHull = game.Opponent.Hull,
									oppCharges = Charges(game.Opponent), cash = game.Commander.Cash, record = game.Commander.PoliceRecordScore,
									reputation = game.Commander.ReputationScore, contAttack = game.EncounterContinueAttacking, contFlee = game.EncounterContinueFleeing });
								game.EncounterContinueAttacking = false; game.EncounterContinueFleeing = false;
								if (result != EncounterResult.Continue) break;
							}
							fights.Add(new { warp, oppType = (int)ot, encounterType = (int)et, flee, variant, start, rounds });
						}
					}
					list.Add(new { seed, difficulty = (int)d, fights });
				}
			}
			Harness.Policy = _ => DialogResult.Yes;
			return list;
		}

		public static object ShipDumpPublic(Ship sh) => ShipDump(sh);

		/// Journeys: repeated warps to the first in-range destination after a rotating offset. Encounters are recorded
		/// by the FormEncounter stub (which returns Normal without fighting), so this exercises warp, departure,
		/// per-click repairs, encounter determination, opponent generation and the arrival pipeline.
		static object Travel()
		{
			Harness.Policy = _ => DialogResult.Yes;
			var list = new List<object>();
			foreach (int seed in new[] { 2, 9, 42 })
			{
				foreach (Difficulty d in new[] { Difficulty.Easy, Difficulty.Normal, Difficulty.Impossible })
				{
					SeedRandom(seed);
					var game = new Game("Harness", d, 5, 5, 5, 5, new SpaceTrader());
					game.Options.AlwaysIgnoreTraders = false;
					var warps = new List<object>();
					for (int w = 0; w < 25; w++)
					{
						game.Commander.Ship.Fuel = game.Commander.Ship.FuelTanks;
						game.Commander.Cash = Math.Max(game.Commander.Cash, 20000);
						game.Commander.PoliceRecordScore = w % 5 == 4 ? -12 : game.Commander.PoliceRecordScore;
						game.Commander.Ship.Hull = Math.Max(1, game.Commander.Ship.Hull - (w % 3) * 7);
						int[] dest = game.Destinations;
						int target = dest[(w * 7) % dest.Length];
						game.SelectedSystemId = (StarSystemId)target;
						Harness.Encounters.Clear();
						game.Warp(false);
						var sys = game.Commander.CurrentSystem;
						var news = new List<int>(); foreach (object o in game.NewsEvents) news.Add((int)o);
						warps.Add(new { target, encounters = new List<object>(Harness.Encounters), arrived = (int)sys.Id,
							days = game.Commander.Days, cash = game.Commander.Cash, debt = game.Commander.Debt,
							record = game.Commander.PoliceRecordScore, fuel = game.Commander.Ship.Fuel, hull = game.Commander.Ship.Hull,
							shields = Charges(game.Commander.Ship), buy = (int[])game.PriceCargoBuy.Clone(), sell = (int[])game.PriceCargoSell.Clone(),
							stock = (int[])sys.TradeItems.Clone(), news, opponentSkills = (int[])game.Mercenaries[(int)CrewMemberId.Opponent].Skills.Clone() });
					}
					list.Add(new { seed, difficulty = (int)d, warps });
				}
			}
			return list;
		}

		static int[] Charges(Ship sh)
		{
			var l = new List<int>(); foreach (Shield x in sh.Shields) if (x != null) l.Add(x.Charge); return l.ToArray();
		}

		/// StarSystem.SpecialResource hides the value until visited; read the backing field instead.
		static SpecialResource SpecialResourceRaw(StarSystem s)
		{
			FieldInfo f = typeof(StarSystem).GetField("_specialResource", BindingFlags.NonPublic | BindingFlags.Instance);
			return (SpecialResource)f.GetValue(s);
		}
	}
}
