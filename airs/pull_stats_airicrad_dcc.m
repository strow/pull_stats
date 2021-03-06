function pull_stats_airicrad_dcc(year, filter, cfg);
% PULL_STATS_AIRICRAD_RAND Create stats accumulations from rtp
%

addpath /asl/matlib/h4tools
addpath /asl/rtp_prod/airs/utils
addpath /asl/packages/rtp_prod2/util
addpath /home/sergio/MATLABCODE/PLOTTER  %
                                         % equal_area_spherical_bands
addpath /asl/matlib/rtptools  % mmwater_rtp.m

[sID, sTempPath] = genscratchpath();

% check for existence of configuration struct
bCheckConfig = false;
if nargin == 3
    bCheckConfig = true;
end

% record run start datetime in output stats file for tracking
trace.RunDate = datetime('now','TimeZone','local','Format', ...
                         'd-MMM-y HH:mm:ss Z');
trace.Reason = 'Normal pull_stats runs';
if bCheckConfig & isfield(cfg, 'Reason')
    trace.Reason = cfg.Reason;
end

bRunKlayers = true;
klayers_exec = ['/asl/packages/klayersV205/BinV201/' ...
                'klayers_airs_wetwater'];
if bCheckConfig & isfield(cfg, 'klayers') & cfg.klayers == false
    bRunKlayers = false;
end
trace.klayers = bRunKlayers;

trace.droplayers = false;
if bCheckConfig & isfield(cfg, 'droplayers') & cfg.droplayers == true
    trace.droplayers = true;
end

rtpdir = '/asl/rtp/rtp_airicrad_v6/';
if bCheckConfig & isfield(cfg, 'rtpdir')
    rtpdir = cfg.rtpdir;
end

statsdir = '/asl/data/stats/airs/dcc';
if bCheckConfig & isfield(cfg, 'statsdir')
    statsdir = cfg.statsdir;
end

basedir = fullfile(rtpdir, 'dcc', int2str(year));
dayfiles = dir(fullfile(basedir, 'era_airicrad_day*_dcc.rtp'));
ndays = length(dayfiles);
% $$$ ndays = 16;
fprintf(1,'>>> numfiles = %d\n', ndays);

% calculate latitude bins
nbins=20; % gives 2N+1 element array of lat bin boundaries
latbinedges_t = equal_area_spherical_bands(nbins);
latbinedges = latbinedges_t(11:31);
clear latbinedges_t
nlatbins = length(latbinedges)-1;

nchans = 2645;  % AIRICRAD/L1C channel space
nlevs = 101;  % klayers output

% allocate final accumulator arrays
robs = zeros(ndays, nlatbins, nchans);

l1cproc_mean = zeros(ndays, nlatbins, nchans);
l1csreason_mean = zeros(ndays, nlatbins, nchans);

lat_mean = zeros(ndays, nlatbins);
lon_mean = zeros(ndays, nlatbins);
solzen_mean = zeros(ndays, nlatbins);
rtime_mean = zeros(ndays, nlatbins); 
count = zeros(ndays, nlatbins, nchans);
tcc_mean = zeros(ndays, nlatbins);
stemp_mean = zeros(ndays, nlatbins);
ptemp_mean = zeros(ndays, nlatbins, nlevs);
gas1_mean = zeros(ndays, nlatbins, nlevs);
gas3_mean = zeros(ndays, nlatbins, nlevs);
spres_mean = zeros(ndays, nlatbins);
nlevs_mean = zeros(ndays, nlatbins);
iudef4_mean = zeros(ndays, nlatbins);
mmwater_mean = zeros(ndays, nlatbins);
satzen_mean = zeros(ndays, nlatbins);
satazi_mean = zeros(ndays, nlatbins);
plevs_mean = zeros(ndays, nlatbins, nlevs);

iday = 1;
% $$$ for giday = 60:75
for giday = 1:length(dayfiles)
   fprintf(1, '>>> year = %d  :: giday = %d\n', year, giday);
   a = dir(fullfile(basedir,dayfiles(giday).name));
   if a.bytes < 100000
        fprintf(2, '**>> ERROR: short input rtp file %s\n', dayfiles(giday).name); 
        continue;
   end
       
      [h,ha,p,pa] = rtpread(fullfile(basedir,dayfiles(giday).name));
      f = h.vchan;  % AIRS proper frequencies
      
      % sanity check on p.robs1 as read in. (There have been
      % instances where this array is short on the spectral
      % dimension which fails in rad2bt. We trap for this here)
      obs = size(p.robs1);
      chans = size(f);
      if obs(1) ~= chans(1)
          fprintf(2, ['**>> ERROR: obs/vchan spectral channel ' ...
                      'mismatch in %s. Bypassing day.\n'], dayfiles(giday).name);
          continue;
      end
            
      switch filter
        case 1
          k = find(p.iudef(4,:) == 1); % descending node (night)
          sDescriptor='desc';
        case 2
          k = find(p.iudef(4,:) == 1 & p.landfrac == 0); % descending
                                                     % node (night) ocean
          sDescriptor='desc_ocean';
        case 3
          k = find(p.iudef(4,:) == 1 & p.landfrac == 1); % descending node
                                                        % (night), land
          sDescriptor='desc_land';
        case 4
          k = find(p.iudef(4,:) == 0); % ascending node (day)
          sDescriptor='asc';
        case 5
          k = find(p.iudef(4,:) == 0 & p.landfrac == 0); % ascending node
                                                         % (day), ocean
          sDescriptor='asc_ocean';
        case 6
          k = find(p.iudef(4,:) == 0 & p.landfrac == 1); % ascending node
                                                        % (day), land
          sDescriptor='asc_land';
      end

      pp = rtp_sub_prof(p, k);
      clear p;

      % check for empty profile struct after subsetting
      if length(pp.robs1) == 0
          fprintf(2, ['>>> No obs found after filter subset for %s. ' ...
                      'Continuing to next day.\n'], dayfiles(giday).name);
          continue;  % jump to next day
      end
      
      if bRunKlayers
          % klayers kills previous sarta in the rtp structures so
          % we need to save values and re-insert after klayers
          % finishes
          tmp_tcc = pp.tcc;
          tmp_l1cproc = pp.l1cproc;
          tmp_l1csreason = pp.l1csreason;
          
          % run klayers on the rtp data to convert levels -> layers
          fprintf(1, '>>> running klayers... ');
          fn_rtp1 = fullfile(sTempPath, ['airs_' sID '_1.rtp']);
          rtpwrite(fn_rtp1, h,ha,pp,pa);
          clear pp;
          fn_rtp2 = fullfile(sTempPath, ['airs_' sID '_2.rtp']);
          klayers_run = [klayers_exec ' fin=' fn_rtp1 ' fout=' fn_rtp2 ...
                         ' > ' sTempPath '/kout.txt'];
          unix(klayers_run);
          fprintf(1, 'Done\n');

          % Read klayers output into local rtp variables
          [h,ha,pp,pa] = rtpread(fn_rtp2);
          
          f = h.vchan;  % AIRS proper frequencies

          % restore sarta values
          pp.tcc = tmp_tcc;
          pp.l1cproc = tmp_l1cproc;
          pp.l1csreason = tmp_l1csreason;
          clear tmp_tcc tmp_l1cproc tmp_l1csreason;
          
          % get column water
          mmwater = mmwater_rtp(h, pp);

          % Check for obs with layer profiles that go lower than
          % topography. Need to check nlevs and NaN out any layers
          % at or below this level

          % ** Any layers-sensitive variables added in averaging code below must
          % ** be checked here first.
          for i=1:length(pp.nlevs)
              badlayers = pp.nlevs(i) : 101;
              pp.plevs(badlayers, i) = NaN;
              pp.palts(badlayers, i) = NaN;
              pp.gas_1(badlayers, i) = NaN;
              pp.gas_2(badlayers, i) = NaN;
              pp.gas_3(badlayers, i) = NaN;
              pp.gas_4(badlayers, i) = NaN;
              pp.gas_5(badlayers, i) = NaN;
              pp.gas_6(badlayers, i) = NaN;
              pp.gas_12(badlayers, i) = NaN;          
              pp.ptemp(badlayers, i) = NaN;
          end
          
      end

      % Initialize counts
      n = length(pp.rlat);
      count_all = ones(nchans,n);
      for i=1:nchans
         % Find bad channels (l1c incorporates l1b calnum by
         % inserting interpolated values for any place where l1b
         % would be 'bad'. i.e. there should be no 'bad' channels)
         k = find( pp.robs1(i,:) == -9999);
%          % These are the good channels
%          kg = setdiff(1:n,k);
% NaN's for bad channels
         pp.robs1(i,k) = NaN;
         count_all(i,k) = 0;
      end

      % Loop over latitude bins
      for ilat = 1:nlatbins
          % subset based on latitude bin
          inbin = find(pp.rlat > latbinedges(ilat) & pp.rlat <= ...
                     latbinedges(ilat+1));
          p = rtp_sub_prof(pp,inbin);
          bincount = count_all(:,inbin); 
          binwater = mmwater(inbin);

          % Radiance mean and std
          r  = p.robs1;
          
          % spectral
          robs(iday,ilat,:) = nanmean(r,2);

          l1cproc_mean(iday, ilat, :) = nanmean(p.l1cproc, 2);
          l1csreason_mean(iday, ilat, :) = nanmean(p.l1csreason, ...
                                                   2);
          lat_mean(iday,ilat) = nanmean(p.rlat);
          lon_mean(iday,ilat) = nanmean(p.rlon);
          solzen_mean(iday,ilat) = nanmean(p.solzen);
          rtime_mean(iday,ilat)  = nanmean(p.rtime);
          count(iday,ilat,:) = sum(bincount,2)';
          tcc_mean(iday, ilat) = nanmean(p.tcc);
          stemp_mean(iday,ilat) = nanmean(p.stemp);
          ptemp_mean(iday,ilat,:) = nanmean(p.ptemp,2);
          gas1_mean(iday,ilat,:) = nanmean(p.gas_1,2);
          gas3_mean(iday,ilat,:) = nanmean(p.gas_3,2);
          spres_mean(iday,ilat) = nanmean(p.spres);
          nlevs_mean(iday,ilat) = nanmean(p.nlevs);
          iudef4_mean(iday,ilat) = nanmean(p.iudef(4,:));
          mmwater_mean(iday,ilat) = nanmean(binwater);
          satzen_mean(iday,ilat) = nanmean(p.satzen);
          satazi_mean(iday,ilat) = nanmean(p.satazi);          
          plevs_mean(iday,ilat,:) = nanmean(p.plevs,2);
      end  % end loop over latitudes
          iday = iday + 1
end  % giday

outfile = fullfile(statsdir, sprintf('rtp_airicrad_era_rad_kl_%s_dcc_%s', ...
           int2str(year), sDescriptor));
eval_str = ['save ' outfile [' robs *_mean count latbinedges ' ...
                    'trace']];
fprintf(1,'>> Executing save command: %s\n', eval_str);
eval(eval_str);
